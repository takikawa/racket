#lang racket/base
(require "test-utils.rkt" (for-syntax racket/base)
         (utils tc-utils)
         (env type-alias-env type-env-structs tvar-env type-name-env init-envs)
         (rep type-rep)
         (rename-in (types subtype union utils abbrev numeric-tower)
                    [Un t:Un] [-> t:->] [->* t:->*])
         (base-env base-types base-types-extra colon)
         (submod typed-racket/base-env/base-types initialize)
         (for-template (base-env base-types base-types-extra base-env colon))
         (private parse-type)
         rackunit
         (only-in racket/class init init-field field augment)
         racket/dict)

(provide parse-type-tests)

;; HORRIBLE HACK!
;; We are solving the following problem:
;; when we require "base-env.rkt" for template, it constructs the type-alias-env
;; in phase 0 (relative to this module), but populates it with phase -1 identifiers
;; The identifiers are also bound in this module at phase -1, but the comparison for
;; the table is phase 0, so they don't compare correctly

;; The solution is to add the identifiers to the table at phase 0.
;; We do this by going through the table, constructing new identifiers based on the symbol
;; of the old identifier.
;; This relies on the identifiers being bound at phase 0 in this module (which they are,
;; because we have a phase 0 require of "base-env.rkt").
(initialize-type-names)
(for ([pr (type-alias-env-map cons)])
  (let ([nm (car pr)]
        [ty (cdr pr)])
    (register-resolved-type-alias (datum->syntax #'here (syntax->datum nm)) ty)))


(define-syntax (run-one stx)
  (syntax-case stx ()
    [(_ ty) (syntax/loc stx
              (parameterize ([current-tvars initial-tvar-env]
                             [current-orig-stx #'ty]
                             [orig-module-stx #'ty]
                             [expanded-module-stx #'ty]
                             [delay-errors? #f])
                (parse-type (syntax ty))))]))

(define-syntax (pt-test stx)
  (syntax-case stx (FAIL)
    [(_ FAIL ty-stx)
     (syntax/loc stx (pt-test FAIL ty-stx initial-tvar-env))]
    [(_ FAIL ty-stx tvar-env)
     (quasisyntax/loc stx
       (test-exn #,(format "~a" (syntax->datum #'ty-stx))
                 exn:fail:syntax?
                 (parameterize ([current-tvars tvar-env]
                                [delay-errors? #f])
                   (lambda () (parse-type (quote-syntax ty-stx))))))]
    [(_ ts tv) (syntax/loc stx (pt-test ts tv initial-tvar-env))]
    [(_ ty-stx ty-val tvar-env)
     (quasisyntax/loc
         stx
       (test-case #,(format "~a" (syntax->datum #'ty-stx))
                  (parameterize ([current-tvars tvar-env]
                                 [delay-errors? #f])
                    (check type-equal? (parse-type (quote-syntax ty-stx)) ty-val))))]))

(define-syntax pt-tests
  (syntax-rules ()
    [(_ nm [elems ...] ...)
     (test-suite nm
                 (pt-test elems ...) ...)]))

(define N -Number)
(define B -Boolean)
(define Sym -Symbol)

(define (parse-type-tests)
  (pt-tests
   "parse-type tests"
   [FAIL UNBOUND]
   [FAIL List]
   [FAIL (All (A) (List -> Boolean))]
   [Number N]
   [Any Univ]
   [(List Number String) (-Tuple (list N -String))]
   [(All (Number) Number) (-poly (a) a)]
   [(Number . Number) (-pair N N)]
   [(Listof Boolean) (make-Listof  B)]
   [(Vectorof (Listof Symbol)) (make-Vector (make-Listof Sym))]
   [(pred Number) (make-pred-ty N)]
   [(-> (values Number Boolean Number)) (t:-> (-values (list N B N)))]
   [(Number -> Number) (t:-> N N)]
   [(Number -> Number) (t:-> N N)]
   [(All (A) Number -> Number) (-poly (a) (t:-> N N))]
   [(All (A) (Number -> Number)) (-poly (a) (t:-> N N))]
   [(All (A) A -> A) (-poly (a) (t:-> a a))]
   [(All (A) A → A) (-poly (a) (t:-> a a))]
   [(All (A) (A -> A)) (-poly (a) (t:-> a a))]
   ;; requires transformer time stuff that doesn't work
   #;[(Refinement even?) (make-Refinement #'even?)]
   [(Number Number Number Boolean -> Number) (N N N B . t:-> . N)]
   [(Number Number Number * -> Boolean) ((list N N) N . t:->* . B)]
   ;[((. Number) -> Number) (->* (list) N N)] ;; not legal syntax
   [(U Number Boolean) (t:Un N B)]
   [(U Number Boolean Number) (t:Un N B)]
   [(U Number Boolean 1) (t:Un N B)]
   [(All (a) (Listof a)) (-poly (a) (make-Listof  a))]
   [(All (a ...) (a ... a -> Integer)) (-polydots (a) ( (list) (a a) . ->... . -Integer))]
   [(∀ (a) (Listof a)) (-poly (a) (make-Listof  a))]
   [(∀ (a ...) (a ... a -> Integer)) (-polydots (a) ( (list) (a a) . ->... . -Integer))]
   [(All (a ...) (a ... -> Number))
    (-polydots (a) ((list) [a a] . ->... . N))]
   [(All (a ...) (-> (values a ...)))
    (-polydots (a) (t:-> (make-ValuesDots (list) a 'a)))]
   [(case-lambda (Number -> Boolean) (Number Number -> Number)) (cl-> [(N) B]
                                                                      [(N N) N])]
   [(case-> (Number -> Boolean) (Number Number -> Number)) (cl-> [(N) B]
                                                                 [(N N) N])]
   [1 (-val 1)]
   [#t (-val #t)]
   [#f (-val #f)]
   ["foo" (-val "foo")]
   ['(1 2 3) (-Tuple (map -val '(1 2 3)))]

   [(Listof Number) (make-Listof  N)]

   [a (-v a) (dict-set initial-tvar-env 'a (-v a))]
   [(All (a ...) (a ... -> Number))
    (-polydots (a) ((list) [a a] . ->... . N))]

   [(Any -> Boolean : Number) (make-pred-ty -Number)]
   [(Any -> Boolean : #:+ (Number @ 0) #:- (! Number @ 0))
    (make-pred-ty -Number)]
   [(Any -> Boolean : #:+ (! Number @ 0) #:- (Number @ 0))
    (t:->* (list Univ) -Boolean : (-FS (-not-filter -Number 0 null) (-filter -Number 0 null)))]
   [(Number -> Number -> Number)
    (t:-> -Number (t:-> -Number -Number))]
   [(Integer -> (All (X) (X -> X)))
    (t:-> -Integer (-poly (x) (t:-> x x)))]

   [(Opaque foo?) (make-Opaque #'foo?)]
   ;; PR 14122
   [FAIL (Opaque 3)]

   ;;; Classes
   [(Class) (make-Class #f null null null null)]
   [(Class (init [x Number] [y Number]))
    (make-Class #f `((x ,-Number #f) (y ,-Number #f)) null null null)]
   [(Class (init [x Number] [y Number #:optional]))
    (make-Class #f `((x ,-Number #f) (y ,-Number #t)) null null null)]
   [(Class (init [x Number]) (init-field [y Number]))
    (make-Class #f `((x ,-Number #f) (y ,-Number #f)) `((y ,-Number))
                null null)]
   [(Class [m (Number -> Number)])
    (make-Class #f null null `((m ,(t:-> N N))) null)]
   [(Class [m (Number -> Number)] (init [x Number]))
    (make-Class #f `((x ,-Number #f)) null `((m ,(t:-> N N))) null)]
   [(Class [m (Number -> Number)] (field [x Number]))
    (make-Class #f null `((x ,-Number)) `((m ,(t:-> N N))) null)]
   [(Class (augment [m (Number -> Number)]))
    (make-Class #f null null null `((m ,(t:-> N N))))]
   [(Class (augment [m (Number -> Number)]) (field [x Number]))
    (make-Class #f null `((x ,-Number)) null `((m ,(t:-> N N))))]
   [(Class (augment [m (-> Number)]) [m (-> Number)])
    (make-Class #f null null `((m ,(t:-> N))) `((m ,(t:-> N))))]
   [FAIL (Class foobar)]
   [FAIL (Class [x UNBOUND])]
   [FAIL (Class [x Number #:random-keyword])]
   [FAIL (Class (random-clause [x Number]))]
   [FAIL (Class [m Number])]
   [FAIL (Class (augment [m Number]))]
   ;; test duplicates
   [FAIL (Class [x Number] [x Number])]
   [FAIL (Class (init [x Number]) (init [x Number]))]
   [FAIL (Class (init [x Number]) (init-field [x Number]))]
   [FAIL (Class (field [x Number]) (init-field [x Number]))]
   [FAIL (Class (augment [m (-> Number)] [m (-> Number)]))]
   [FAIL (Class (augment [m (-> Number)]) (augment [m (-> Number)]))]
   [FAIL (Class [m (-> Number)] [m (-> Number)])]
   ;; test #:row-var
   [(All (r #:row) (Class #:row-var r))
    (make-PolyRow (list 'r)
                  (list null null null null)
                  (make-Class (make-F 'r) null null null null))]
   [(All (r #:row) (Class #:implements (Class #:row-var r)))
    (make-PolyRow (list 'r)
                  (list null null null null)
                  (make-Class (make-F 'r) null null null null))]
   [(All (r #:row) (Class #:implements (Class) #:row-var r))
    (make-PolyRow (list 'r)
                  (list null null null null)
                  (make-Class (make-F 'r) null null null null))]
   [FAIL (Class #:row-var 5)]
   [FAIL (Class #:row-var (list 3))]
   [FAIL (Class #:implements (Class #:row-var r) #:row-var x)]
   [FAIL (Class #:implements (Class #:row-var r) #:row-var r)]
   [FAIL (All (r #:row)
           (All (x #:row)
            (Class #:implements (Class #:row-var r) #:row-var x)))]
   [FAIL (All (r #:row) (Class #:implements (Class #:row-var r) #:row-var r))]
   ;; test #:implements
   [(Class #:implements (Class [m (Number -> Number)]) (field [x Number]))
    (make-Class #f null `((x ,-Number)) `((m ,(t:-> N N))) null)]
   [(Class #:implements (Class [m (Number -> Number)])
           #:implements (Class [n (Number -> Number)])
           (field [x Number]))
    (make-Class #f null `((x ,-Number))
                `((n ,(t:-> N N)) (m ,(t:-> N N))) null)]
   [(Class #:implements (Class [m (Number -> Number)])
           #:implements (Class [m (Number -> Number)])
           (field [x Number]))
    (make-Class #f null `((x ,-Number)) `((m ,(t:-> N N))) null)]
   [(Class #:implements (Class (init [x Integer]) [m (Number -> Number)])
           (field [x Number]))
    (make-Class #f null `((x ,-Number)) `((m ,(t:-> N N))) null)]
   [FAIL (Class #:implements Number)]
   [FAIL (Class #:implements Number [m (Number -> Number)])]
   [FAIL (Class #:implements (Class [m (Number -> Number)]) [m String])]
   [FAIL (Class #:implements (Class [m (Number -> Number)])
                #:implements (Class [m (String -> String)])
                (field [x Number]))]
   [FAIL (Class #:implements (Class (augment [m (Number -> Number)]))
                #:implements (Class (augment [m (String -> String)]))
                (field [x Number]))]
   [FAIL (Class #:implements (Class (augment [m (Number -> Number)]))
                (augment [m (-> Number)]))]
   ;; Test Object types
   [(Object) (make-Instance (make-Class #f null null null null))]
   [(Object [m (Number -> Number)])
    (make-Instance (make-Class #f null null `((m ,(t:-> N N))) null))]
   [(Object [m (Number -> Number)] (field [f Number]))
    (make-Instance (make-Class #f null `((f ,N))
                               `((m ,(t:-> N N))) null))]
   [FAIL (Object foobar)]
   [FAIL (Object [x UNBOUND])]
   [FAIL (Object [x Number #:random-keyword])]
   [FAIL (Object (random-clause [x Number]))]
   [FAIL (Object [x Number] [x Number])]
   [FAIL (Object (field [x Number]) (field [x Number]))]
   [FAIL (Object [x Number] [x Number])]
   [FAIL (Object [m Number])]
   ;; Test row polymorphic types
   [(All (r #:row) ((Class #:row-var r) -> (Class #:row-var r)))
    (-polyrow (r) (list null null null null)
      (t:-> (make-Class r null null null null)
            (make-Class r null null null null)))]
   [(All (r #:row (init x y z) (field f) m n)
      ((Class #:row-var r) -> (Class #:row-var r)))
    (-polyrow (r) (list '(x y z) '(f) '(m n) '())
      (t:-> (make-Class r null null null null)
            (make-Class r null null null null)))]
   ;; Class types cannot use a row variable that doesn't constrain
   ;; all of its members to be absent in the row
   [FAIL (All (r #:row (init x))
           ((Class #:row-var r (init y)) -> (Class #:row-var r)))]
   [FAIL (All (r #:row (init x y z) (field f) m n)
           ((Class #:row-var r a b c) -> (Class #:row-var r)))]))

;; FIXME - add tests for parse-values-type, parse-tc-results

(define-go
  parse-type-tests)



