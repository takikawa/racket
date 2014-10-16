#lang racket/base

;; Provides functionality to take a static contract and turn it into a regular contract.

(require
  data/queue
  racket/function
  racket/match
  racket/dict
  racket/sequence
  racket/contract
  racket/syntax
  (for-template racket/base racket/contract)
  "combinators.rkt"
  "kinds.rkt"
  "parametric-check.rkt"
  "structures.rkt"
  "constraints.rkt"
  "equations.rkt")

(provide
  (contract-out
    [instantiate
      (parametric->/c (a) ((static-contract? (-> #:reason (or/c #f string?) a))
                           (contract-kind? #:cache hash?)
                           . ->* . (values (listof syntax?) (or/c a syntax?))))]))

;; Providing these so that tests can work directly with them.
(module* internals #f
  (provide compute-constraints
           compute-recursive-kinds
           instantiate/inner))

;; kind is the greatest kind of contract that is supported, if a greater kind would be produced the
;; fail procedure is called.
(define (instantiate sc fail [kind 'impersonator] #:cache [cache (make-hash)])
  (if (parametric-check sc)
      (fail #:reason "multiple parametric contracts are not supported")
      (with-handlers [(exn:fail:constraint-failure?
                        (lambda (exn) (fail #:reason (exn:fail:constraint-failure-reason exn))))]
        (instantiate/inner sc
          (compute-recursive-kinds
            (contract-restrict-recursive-values (compute-constraints sc kind)))
          cache))))

(define (compute-constraints sc max-kind)
  (define memo-table (make-hash))
  (define (recur sc)
    (cond [(hash-ref memo-table sc #f)]
          [else
           (define result
             (match sc
               [(recursive-sc names values body)
                (close-loop names (map recur values) (recur body))]
               [(? sc?)
                (sc->constraints sc recur)]))
           (hash-set! memo-table sc result)
           result]))
  (define constraints (recur sc))
  (displayln "done constraints")
  #;(validate-constraints (add-constraint constraints max-kind))
  constraints)


(define (compute-recursive-kinds recursives)
  (define eqs (make-equation-set))
  (define vars
    (for/hash ([(name _) (in-dict recursives)])
      (values name (add-variable! eqs 'flat))))

  (define (lookup id)
    (variable-ref (hash-ref vars id)))

  (for ([(name v) (in-dict recursives)])
    (match v
      [(kind-max others max)
       (add-equation! eqs
          (hash-ref vars name)
          (lambda ()
            (apply combine-kinds max (map lookup (dict-keys others)))))]))
  (define var-values (resolve-equations eqs))
  (for/hash (((name var) (in-hash vars)))
    (values name (hash-ref var-values var))))


;; SC Listof<RecKind> Hash<SC, List<Id, Nat, Stx>> -> Listof<Stx> Stx
(define (instantiate/inner sc recursive-kinds cache)
  (define bound-names (make-parameter '()))
  ;; sc-queue : Queue<SC>
  ;; Records the order in which to return cached syntax objects
  (define sc-queue (make-queue))
  (define (recur sc)
    (cond [(hash-ref cache sc #f) => car]
          [(arr/sc? sc) (make-contract sc)]
          [(parameteric->/sc? sc)
           (match-define (parametric->/sc: vars _) sc)
           (parameterize ([bound-names (append vars (bound-names))])
             (make-contract sc))]
          ;; If any names are bound, the contract can't be lifted out
          ;; because it depends on being in the scope of the names
          [(ormap (λ (n) (name-free-in? n sc)) (bound-names))
           ;(printf "free case ~a~n" sc)
           #;
           (when (match sc [(recursive-sc-use _) #t] [_ #f])
             (displayln "recursive use"))
           (make-contract sc)]
          [else
           ;(printf "cache case ~a~n" sc)
           (define ctc (make-contract sc))
           (when (identifier? ctc)
             (printf "caching this, ~a (names: )~n" ctc #;(bound-names)
                     ))
           (define fresh-id (generate-temporary))
           (hash-set! cache sc (cons fresh-id ctc))
           (enqueue! sc-queue sc)
           fresh-id]))
  (define (make-contract sc)
    (match sc
      [(recursive-sc names values body)
       (define raw-names (generate-temporaries names))
       (define raw-bindings
         (parameterize ([bound-names (append names (bound-names))])
           (for/list ([raw-name (in-list raw-names)]
                      [value (in-list values)])
             #`[#,raw-name #,(recur value)])))
       (define bindings
         (for/list ([name (in-list names)]
                    [raw-name (in-list raw-names)])
           #`[#,name (recursive-contract #,raw-name
                                         #,(kind->keyword
                                            (hash-ref recursive-kinds name)))]))
       #`(letrec (#,@bindings #,@raw-bindings)
           #,(parameterize ([bound-names (append names (bound-names))])
               (recur body)))]
      [(? sc? sc)
       (sc->contract sc recur)]))
  (define ctc (recur sc))
  (values (for/list ([sc (in-queue sc-queue)])
            (match-define (cons id ctc) (hash-ref cache sc))
            #`(define #,id #,ctc))
          ctc))

(require racket/control)

;; determine if a given name is free in the sc
(define memo-table (make-hash))
(define (name-free-in? name sc)
  (define tag (make-continuation-prompt-tag))
  (define (free? sc _)
    (cond [(hash-ref memo-table (list sc name) #f)
           => (λ (x) (fcontrol (eq? x 'free) #:tag tag))]
          [else
           (match sc
             [(or (recursive-sc-use name*) (parametric-var/sc: name*))
              #:when (free-identifier=? name name*)
              (printf "free-id ~a ~a~n" name name*)
              (hash-set! memo-table (list sc name) 'free)
              (fcontrol #t #:tag tag)]
             [_
              (% (sc-traverse sc free?)
                 (λ (v k)
                   (cond [v
                          (hash-set! memo-table (list sc name) 'free)
                          (fcontrol #t #:tag tag)]
                         [else (k (void))]))
                 #:tag tag)
              (hash-set! memo-table (list sc name) 'non-free)
              (fcontrol #f #:tag tag)])]))
  (% (free? sc 'dummy)
     (λ (v _) v)
     #:tag tag))
