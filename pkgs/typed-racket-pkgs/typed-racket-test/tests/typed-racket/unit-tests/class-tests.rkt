#lang racket

;; Unit tests for typed classes
;;
;; FIXME: make this work with the unit testing framework for
;;        typecheck eventually (it's finnicky).
;;
;; FIXME: these tests are slow

(require "test-utils.rkt"
         rackunit
         (for-syntax syntax/parse))

(provide class-tests)

(define test-error-port (make-parameter (open-output-nowhere)))

(define-syntax-rule (run/tr-module e ...)
  (parameterize ([current-output-port (open-output-nowhere)]
                 [current-error-port (test-error-port)])
    (define ns (make-base-namespace))
    (eval (quote (module typed typed/racket
                   e ...))
          ns)
    (eval (quote (require 'typed)) ns)))

(define-syntax-rule (check-ok e ...)
  (begin (check-not-exn (thunk (run/tr-module e ...)))))

(define-syntax (check-err stx)
  (syntax-parse stx
    [(_ #:exn rx-or-pred e ...)
     #'(parameterize ([test-error-port (open-output-string)])
         (check-exn
          (λ (exn)
            (cond [(regexp? rx-or-pred)
                   (and (exn:fail:syntax? exn)
                        (or (regexp-match? rx-or-pred (exn-message exn))
                            (regexp-match?
                             rx-or-pred
                             (get-output-string (test-error-port)))))]
                  [(procedure? rx-or-pred)
                   (and (exn:fail:syntax? exn)
                        (rx-or-pred exn))]
                  [else (error "expected predicate or regexp")]))
          (thunk (run/tr-module e ...))))]
    [(_ e ...)
     #'(check-exn
        exn:fail:syntax?
        (thunk (run/tr-module e ...)))]))

(define (class-tests)
  (test-suite
   "Class type-checking tests"

   ;; Basic class with init and public method
   (check-ok
    (: c% (Class (init [x Integer])
                 [m (Integer -> Integer)]))
    (define c%
      (class object%
        (super-new)
        (init x)
        (define/public (m x) 0)))
    (send (new c% [x 1]) m 5))

   ;; Fails, bad superclass expression
   (check-err #:exn #rx"expected a superclass but"
    (: d% (Class (init [x Integer])
                 [m (Integer -> Integer)]))
    (define d% (class 5
                 (super-new)
                 (init x)
                 (define/public (m x) 0))))

   ;; Method using argument type
   (check-ok
    (: e% (Class (init [x Integer])
                 [m (Integer -> Integer)]))
    (define e% (class object%
                 (super-new)
                 (init x)
                 (define/public (m x) x))))

   ;; Send inside a method
   (check-ok
    (: f% (Class (init [x Integer])
                 [m (Integer -> Integer)]))
    (define f% (class object%
                 (super-new)
                 (init x)
                 (define/public (m x) (send this m 3)))))

   ;; Fails, send to missing method
   (check-err #:exn #rx"method z not understood"
    (: g% (Class (init [x Integer #:optional])
                 [m (Integer -> Integer)]))
    (define g% (class object%
                 (super-new)
                 (init [x 0])
                 (define/public (m x) (send this z)))))

   ;; Send to other methods
   (check-ok
    (: h% (Class [n (-> Integer)]
                 [m (Integer -> Integer)]))
    (define h% (class object%
                 (super-new)
                 (define/public (n) 0)
                 (define/public (m x) (send this n)))))

   ;; Local sends
   (check-ok
    (: i% (Class [n (-> Integer)]
                 [m (Integer -> Integer)]))
    (define i% (class object%
                 (super-new)
                 (define/public (n) 0)
                 (define/public (m x) (n)))))

   ;; Field access via get-field
   (check-ok
    (: j% (Class (field [n Integer])
                 [m (-> Integer)]))
    (define j% (class object%
                 (super-new)
                 (field [n 0])
                 (define/public (m) (get-field n this)))))

   ;; fails, field's default value has wrong type
   (check-err #:exn #rx"Expected Integer, but got String"
    (class object% (super-new)
      (: x Integer)
      (field [x "foo"])))

   ;; Fail, field access to missing field
   (check-err #:exn #rx"expected an object with field n"
    (: k% (Class [m (-> Integer)]))
    (define k% (class object%
                 (super-new)
                 (define/public (m) (get-field n this)))))

   ;; Fail, conflict with parent field
   (check-err #:exn #rx"defines conflicting public field n"
    (: j% (Class (field [n Integer])
                 [m (-> Integer)]))
    (define j% (class object%
                 (super-new)
                 (field [n 0])
                 (define/public (m) (get-field n this))))
    (: l% (Class (field [n Integer])
                 [m (-> Integer)]))
    (define l% (class j%
                 (field [n 17])
                 (super-new))))

   ;; Fail, conflict with parent method
   (check-err #:exn #rx"defines conflicting public method m"
    (: j% (Class [m (-> Integer)]))
    (define j% (class object%
                 (super-new)
                 (define/public (m) 15)))
    (: m% (Class [m (-> Integer)]))
    (define m% (class j%
                 (super-new)
                 (define/public (m) 17))))

   ;; Inheritance
   (check-ok
    (: j% (Class (field [n Integer])
                 [m (-> Integer)]))
    (define j% (class object%
                 (super-new)
                 (field [n 0])
                 (define/public (m) (get-field n this))))
    (: n% (Class (field [n Integer])
                 [m (-> Integer)]))
    (define n% (class j% (super-new))))

   ;; should fail, too many methods
   (check-err
    #:exn #rx"public method m that is not in the expected type"
    (: o% (Class))
    (define o% (class object%
                 (super-new)
                 (define/public (m) 0))))

   ;; same as previous
   (check-err
    #:exn #rx"public method n that is not in the expected type"
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m x) (add1 x))
                 (define/public (n) 0))))

   ;; fails, too many inits
   (check-err
    #:exn #rx"initialization argument x that is not in the expected type"
    (: c% (Class))
    (define c% (class object% (super-new)
                 (init x))))

   ;; fails, init should be optional but is mandatory
   (check-err #:exn #rx"missing optional init argument str"
    (: c% (Class (init [str String #:optional])))
    (define c% (class object% (super-new)
                 (init str))))

   ;; fails, too many fields
   (check-err
    #:exn #rx"public field x that is not in the expected type"
    (: c% (Class (field [str String])))
    (define c% (class object% (super-new)
                 (field [str "foo"] [x 0]))))

   ;; test that an init with no annotation still type-checks
   ;; (though it will have the Any type)
   (check-ok
     (define c% (class object% (super-new) (init x))))

   ;; test that a field with no annotation still type-checks
   ;; (though it will have the Any type)
   (check-ok
     (define c% (class object% (super-new) (field [x 0]))))

   ;; Mixin on classes without row polymorphism
   (check-ok
     (: mixin ((Class [m (-> Integer)])
               ->
               (Class [m (-> Integer)]
                      [n (-> String)])))
     (define (mixin cls)
       (class cls
         (super-new)
         (define/public (n) "hi")))

     (: arg-class% (Class [m (-> Integer)]))
     (define arg-class%
       (class object%
         (super-new)
         (define/public (m) 0)))

     (mixin arg-class%))

   ;; Fail, bad mixin
   (check-err #:exn #rx"missing public method n"
     (: mixin ((Class [m (-> Integer)])
               ->
               (Class [m (-> Integer)]
                      [n (-> String)])))
     (define (mixin cls)
       (class cls
         (super-new)))

     (: arg-class% (Class [m (-> Integer)]))
     (define arg-class%
       (class object%
         (super-new)
         (define/public (m) 0)))

     (mixin arg-class%))

   ;; Fail, bad mixin argument
   (check-err #:exn #rx"Expected \\(Class \\(m \\(-> Integer\\)\\)\\)"
     (: mixin ((Class [m (-> Integer)])
               ->
               (Class [m (-> Integer)]
                      [n (-> String)])))
     (define (mixin cls)
       (class cls
         (super-new)
         (define/public (n) "hi")))

     (: arg-class% (Class [k (-> Integer)]))
     (define arg-class%
       (class object%
         (super-new)
         (define/public (k) 0)))

     (mixin arg-class%))

   ;; classes that don't use define/public directly
   (check-ok
     (: c% (Class [m (Number -> String)]))
     (define c%
       (class object%
         (super-new)
         (public m)
         (define-values (m)
           (lambda (x) (number->string x)))))
     (send (new c%) m 4))

   ;; check that classes work in let clauses
   (check-ok
    (let: ([c% : (Class [m (Number -> String)])
            (class object%
              (super-new)
              (public m)
              (define-values (m)
                (lambda (x) (number->string x))))])
      (send (new c%) m 4)))

   ;; check a good super-new call
   (check-ok
    (: c% (Class (init [x Integer])))
    (define c% (class object% (super-new) (init x)))
    (: d% (Class))
    (define d% (class c% (super-new [x (+ 3 5)]))))

   ;; fails, missing super-new
   (check-err #:exn #rx"typed classes must call super-new"
    (: c% (Class (init [x Integer])))
    (define c% (class object% (init x))))

   ;; fails, non-top-level super-new
   ;; FIXME: this case also spits out additional untyped identifier
   ;;        errors which should be squelched maybe
   (check-err #:exn #rx"typed classes must call super-new"
    (: c% (Class (init [x Integer])))
    (define c% (class object% (let () (super-new)) (init x))))

   ;; fails, bad super-new argument
   (check-err #:exn #rx"Expected Integer, but got String"
    (: c% (Class (init [x Integer])))
    (define c% (class object% (super-new) (init x)))
    (: d% (Class))
    (define d% (class c% (super-new [x "bad"]))))

   ;; fails, positional super construction not allowed
   (check-err #:exn #rx"positional arguments for super"
     (class object% (super-instantiate ((+ 1 2) 4)) (field [x : Integer 0])))

   ;; fails, same reason as previous
   (check-err #:exn #rx"positional arguments for super"
     (class object% (super-make-object (+ 1 2) 4) (field [x : Integer 0])))

   ;; test override
   (check-ok
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) (add1 y))))
    (: d% (Class [m (Integer -> Integer)]))
    (define d% (class c% (super-new)
                 (define/override (m y) (* 2 y)))))

   ;; test local call to overriden method
   (check-ok
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) (add1 y))))
    (: d% (Class [n (Integer -> Integer)]
                 [m (Integer -> Integer)]))
    (define d% (class c% (super-new)
                 (define/public (n x) (m x))
                 (define/override (m y) (* 2 y)))))

   ;; fails, superclass missing public for override
   (check-err #:exn #rx"superclass missing overridable method m"
    (: d% (Class [m (Integer -> Integer)]))
    (define d% (class object% (super-new)
                 (define/override (m y) (* 2 y)))))

   ;; local field access and set!
   (check-ok
    (: c% (Class (field [x Integer])
                 [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (field [x 0])
                 (define/public (m y)
                   (begin0 x (set! x (+ x 1)))))))

   ;; test top-level expressions in the class
   (check-ok
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) 0)
                 (+ 3 5))))

   ;; test top-level method call
   (check-ok
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) 0)
                 (m 3))))

   ;; test top-level field access
   (check-ok
    (: c% (Class (field [f String])))
    (define c% (class object% (super-new)
                 (field [f "foo"])
                 (string-append f "z"))))

   ;; fails, bad top-level expression
   (check-err #:exn #rx"Expected Number, but got String"
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) 0)
                 (+ "foo" 5))))

   ;; fails, ill-typed method call
   (check-err #:exn #rx"Expected Integer, but got String"
    (: c% (Class [m (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (define/public (m y) 0)
                 (m "foo"))))

   ;; fails, ill-typed field access
   (check-err #:exn #rx"Expected String, but got Positive-Byte"
    (: c% (Class (field [f String])))
    (define c% (class object% (super-new)
                 (field [f "foo"])
                 (set! f 5))))

   ;; test private field
   (check-ok
    (class object%
      (super-new)
      (: x Integer)
      (define x 5)
      (set! x 8)
      (+ x 1))
    (: d% (Class (field [y String])))
    (define d%
      (class object%
        (super-new)
        (: x Integer)
        (define x 5)
        (: y String)
        (field [y "foo"]))))

   ;; fails, bad private field set!
   (check-err #:exn #rx"Expected Integer, but got String"
    (class object%
      (super-new)
      (: x Integer)
      (define x 5)
      (set! x "foo")))

   ;; fails, bad private field default
   (check-err #:exn #rx"Expected Integer, but got String"
    (class object%
      (super-new)
      (: x Integer)
      (define x "foo")))

   ;; fails, private field needs type annotation
   (check-err #:exn #rx"Expected Nothing"
    (class object%
      (super-new)
      (define x "foo")))

   ;; test private method
   (check-ok
    (class object% (super-new)
      (: x (-> Integer))
      (define/private (x) 3)
      (: m (-> Integer))
      (define/public (m) (x))))

   ;; fails, public and private types conflict
   (check-err #:exn #rx"Expected String, but got Integer"
    (class object% (super-new)
      (: x (-> Integer))
      (define/private (x) 3)
      (: m (-> String))
      (define/public (m) (x))))

   ;; fails, not enough annotation on private
   (check-err #:exn #rx"Cannot apply expression of type Any"
    (class object% (super-new)
      (define/private (x) 3)
      (: m (-> Integer))
      (define/public (m) (x))))

   ;; fails, ill-typed private method implementation
   (check-err #:exn #rx"Expected Integer, but got String"
    (class object% (super-new)
      (: x (-> Integer))
      (define/private (x) "bad result")))

   ;; test optional init arg
   (check-ok
    (: c% (Class (init [x Integer #:optional])))
    (define c% (class object% (super-new)
                 (: x Integer)
                 (init [x 0]))))

   ;; test init coverage when all optionals are
   ;; in the superclass
   (check-ok
    (: c% (Class (init [x Integer #:optional])))
    (: d% (Class (init [x Integer #:optional])))
    (define c% (class object% (super-new)
                 (: x Integer)
                 (init [x 0])))
    (define d% (class c% (super-new))))

   ;; fails, expected mandatory but got optional
   (check-err
    #:exn #rx"optional init argument x that is not in the expected type"
    (: c% (Class (init [x Integer])))
    (define c% (class object% (super-new)
                 (: x Integer)
                 (init [x 0]))))

   ;; fails, mandatory init not provided
   (check-err #:exn #rx"value not provided for named init arg x"
    (define d% (class object% (super-new)
                 (: x Integer)
                 (init x)))
    (new d%))

   ;; test that provided super-class inits don't count
   ;; towards the type of current class
   (check-ok
    (: c% (Class))
    (define c% (class (class object% (super-new)
                        (: x Integer)
                        (init x))
                 (super-new [x 3]))))

   ;; fails, super-class init already provided
   (check-err
    (define c% (class (class object% (super-new)
                        (: x Integer)
                        (init x))
                 (super-new [x 3])))
    (new c% [x 5]))

   ;; fails, super-new can only be called once per class
   (check-err
    (class object%
      (super-new)
      (super-new)))

   ;; test passing an init arg to super-new
   (check-ok
    (define c% (class (class object% (super-new)
                        (: x Integer)
                        (init x))
                 (: x Integer)
                 (init x)
                 (super-new [x x])))
    (new c% [x 5]))

   ;; fails, bad argument type to super-new
   (check-err
    (define c% (class (class object% (super-new)
                        (: x Integer)
                        (init x))
                 (: x String)
                 (init x)
                 (super-new [x x]))))

   ;; test inherit method
   (check-ok
    (class (class object% (super-new)
             (: m (Integer -> Integer))
             (define/public (m x) (add1 x)))
      (super-new)
      (inherit m)
      (m 5)))

   ;; test internal name with inherit
   (check-ok
    (class (class object% (super-new)
             (: m (Integer -> Integer))
             (define/public (m x) (add1 x)))
      (super-new)
      (inherit [n m])
      (n 5)))

   ;; test inherit field
   (check-ok
    (class (class object% (super-new)
             (field [x : Integer 0]))
      (super-new)
      (inherit-field x)))

   ;; test internal name with inherit-field
   (check-ok
    (class (class object% (super-new)
             (field [x : Integer 0]))
      (super-new)
      (inherit-field [y x])
      (set! y 1)))

   ;; fails, superclass missing inherited field
   (check-err #:exn #rx"superclass missing field"
    (class (class object% (super-new))
      (super-new)
      (inherit-field [y x])))

   ;; fails, missing super method for inherit
   (check-err
    (class (class object% (super-new)) (super-new) (inherit z)))

   ;; fails, bad argument type to inherited method
   (check-err
    (class (class object% (super-new)
             (: m (Integer -> Integer))
             (define/public (m x) (add1 x)))
      (super-new)
      (inherit m)
      (m "foo")))

   ;; test that keyword methods type-check
   ;; FIXME: send with keywords does not work yet
   (check-ok
    (: c% (Class [n (Integer #:foo Integer -> Integer)]))
    (define c%
      (class object%
        (super-new)
        (define/public (n x #:foo foo)
          (+ foo x)))))

   ;; test instance subtyping
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: x (U False Number))
        (field [x 0])))
    (: x (Instance (Class)))
    (define x (new c%)))

   ;; test use of `this` in field default
   (check-ok
    (class object%
      (super-new)
      (: x Integer)
      (field [x 0])
      (: y Integer)
      (field [y (get-field x this)])))

   ;; test super calls
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/public (m x) 0)))
    (define d%
      (class c%
        (super-new)
        (define/override (m x) (add1 (super m 5)))))
    (send (new d%) m 1))

   ;; test super calls at top-level
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/public (m x) 0)))
    (define d%
      (class c%
        (super-new)
        (super m 5)
        (define/override (m x) 5))))

   ;; fails, bad super call argument
   (check-err
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/public (m x) 0)))
    (define d%
      (class c%
        (super-new)
        (super m "foo")
        (define/override (m x) 5))))

   ;; test different internal/external names
   (check-ok
    (define c% (class object% (super-new)
                 (public [m n])
                 (define m (lambda () 0))))
    (send (new c%) n))

   ;; test local calls with internal/external
   (check-ok
    (define c% (class object% (super-new)
                 (: m (-> Integer))
                 (public [m n])
                 (define m (lambda () 0))
                 (: z (-> Integer))
                 (define/public (z) (m))))
    (send (new c%) z))

   ;; internal/external the same is ok
   (check-ok
    (define c% (class object% (super-new)
                 (public [m m])
                 (define m (lambda () 0))))
    (send (new c%) m))

   ;; fails, internal name not accessible
   (check-err
    (define c% (class object% (super-new)
                 (public [m n])
                 (define m (lambda () 0))))
    (send (new c%) m))

   ;; test internal/external with expected
   (check-ok
    (: c% (Class [n (-> Integer)]))
    (define c% (class object% (super-new)
                 (public [m n])
                 (define m (lambda () 0))))
    (send (new c%) n))

   ;; test internal/external field
   (check-ok
    (define c% (class object% (super-new)
                 (: f Integer)
                 (field ([f g] 0))))
    (get-field g (new c%)))

   ;; fail, internal name not accessible
   (check-err
    (define c% (class object% (super-new)
                 (: f Integer)
                 (field ([f g] 0))))
    (get-field f (new c%)))

   ;; test internal/external init
   (check-ok
    (define c% (class object% (super-new)
                 (: i Integer)
                 (init ([i j]))))
    (new c% [j 5]))

   ;; fails, internal name not accessible
   (check-err
    (define c% (class object% (super-new)
                 (: i Integer)
                 (init ([i j]))))
    (new c% [i 5]))

   ;; test init default values
   (check-ok
    (class object% (super-new)
      (: z Integer)
      (init [z 0])))

   ;; fails, bad default init value
   (check-err
    (class object% (super-new)
      (: z Integer)
      (init [z "foo"])))

   ;; test init field default value
   (check-ok
    (define c% (class object% (super-new)
                 (: x Integer)
                 (init-field ([x y] 0)))))

   ;; fails, wrong init-field default
   (check-err
    (define c% (class object% (super-new)
                 (: x Integer)
                 (init-field ([x y] "foo")))))

   ;; test type-checking method with internal/external
   (check-err
    (: c% (Class [n (Integer -> Integer)]))
    (define c% (class object% (super-new)
                 (public [m n])
                 (define m (lambda () 0)))))

   ;; test type-checking without expected class type
   (check-ok
    (define c% (class object% (super-new)
                 (: m (Integer -> Integer))
                 (define/public (m x)
                   0)))
    (send (new c%) m 5))

   ;; fails, because the local call type is unknown
   ;; and is assumed to be Any
   (check-err #:exn #rx"since it is not a function type"
    (class object% (super-new)
            (define/public (m) (n))
            (define/public (n x) 0)))

   ;; test type-checking for classes without any
   ;; internal type annotations on methods
   (check-ok
    (define c% (class object% (super-new)
                 (define/public (m) 0)))
    (send (new c%) m))

   ;; test inheritance without expected
   (check-ok
    (define c% (class (class object% (super-new)
                        (: m (-> Integer))
                        (define/public (m) 0))
                 (super-new)
                 (: n (-> Integer))
                 (define/public (n) 1)))
    (send (new c%) m)
    (send (new c%) n))

   ;; test fields without expected class type
   (check-ok
    (define c% (class object% (super-new)
                 (: x Integer)
                 (field [x 0])))
    (get-field x (new c%)))

   ;; row polymorphism, basic example with instantiation
   (check-ok
    (: f (All (A #:row (field x))
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (inst f #:row (field [y Integer])))

   ;; fails, because the instantiation uses a field that
   ;; is supposed to be absent via the row constraint
   (check-err
    (: f (All (A #:row (field x))
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (inst f #:row (field [x Integer])))

   ;; fails, mixin argument is missing required field
   (check-err
    (: f (All (A #:row (field x))
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (define instantiated
      (inst f #:row (field [y Integer])))
    (instantiated
     (class object% (super-new))))

   ;; mixin application succeeds
   (check-ok
    (: f (All (A #:row (field x))
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (define instantiated
      (inst f #:row (field [y Integer])))
    (instantiated
     (class object% (super-new)
       (: y Integer)
       (field [y 0]))))

   ;; Basic row constraint inference
   (check-ok
    (: f (All (A #:row) ; inferred
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (inst f #:row (field [y Integer])))

   ;; fails, inferred constraint and instantiation don't match
   (check-err
    (: f (All (A #:row)
           ((Class #:row-var A)
            ->
            (Class #:row-var A (field [x Integer])))))
    (define (f cls)
      (class cls (super-new)
        (field [x 5])))
    (inst f #:row (field [x Integer])))

   ;; Check simple use of pubment
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x) 0)))
    (send (new c%) m 3))

   ;; Local calls to pubment method
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x) 0)
        (: n (-> Number))
        (define/public (n) (m 5))))
    (send (new c%) n))

   ;; Inheritance with augment
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x) 0)))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x)
          (+ 1 x))))
    (send (new c%) m 5))

   ;; Pubment with inner
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x)
          (inner 0 m x))))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x)
          (+ 1 x))))
    (send (new c%) m 0))

   ;; make sure augment type is reflected in class type
   (check-ok
     (: c% (Class (augment [m (String -> Integer)])
                  [m (Integer -> Integer)]))
     (define c%
       (class object% (super-new)
         (: m (Integer -> Integer)
            #:augment (String -> Integer))
         (define/pubment (m x) x))))

   ;; pubment with different augment type
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer)
           #:augment (String -> String))
        (define/pubment (m x)
          (inner "" m "foo") 0)))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x)
          (string-append x "bar"))))
    (send (new c%) m 0))

   ;; fail, bad inner argument
   (check-err #:exn #rx"Expected String, but got Integer"
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer)
           #:augment (String -> String))
        (define/pubment (m x)
          (inner "" m x) 0)))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x)
          (string-append x "bar"))))
    (send (new c%) m 0))

   ;; Fail, bad inner default
   (check-err #:exn #rx"Expected Integer, but got String"
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x)
          (inner "foo" m x)))))

   ;; Fail, wrong number of arguments to inner
   (check-err #:exn #rx"Wrong number of arguments, expected 2"
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x)
          (inner 3 m)))))

   ;; Fail, bad augment type
   (check-err #:exn #rx"Expected Integer, but got String"
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/pubment (m x)
          (inner 0 m x))))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x) "bad type"))))

   ;; Fail, cannot augment non-augmentable method
   (check-err #:exn #rx"superclass missing augmentable method m"
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (define/public (m x) 0)))
    (define d%
      (class c%
        (super-new)
        (define/augment (m x) 1))))

   ;; Pubment with separate internal/external names
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (Integer -> Integer))
        (pubment [n m])
        (define n (λ (x) 0))))
    (send (new c%) m 0))

   ;; Pubment with expected class type
   (check-ok
    (: c% (Class [m (Natural -> Natural)]
                 (augment [m (Natural -> Natural)])))
    (define c%
      (class object%
        (super-new)
        (define/pubment (m x) 0)))
    (send (new c%) m 3))

   ;; fails, expected type not a class
   (check-err #:exn #rx"Expected Number"
     (: c% Number)
     (define c%
       (class object%
         (super-new)
         (: x Integer)
         (init-field x))))

   ;; test polymorphic class
   (check-ok
     (: c% (All (A) (Class (init-field [x A]))))
     (define c%
       (class object%
         (super-new)
         (init-field x)))
     (new (inst c% Integer) [x 0]))

   ;; fails due to ill-typed polymorphic class body
   (check-err #:exn #rx"Expected A, but got Positive-Byte"
     (: c% (All (A) (Class (init-field [x A]))))
     (define c%
       (class object%
         (super-new)
         (init-field x)
         (set! x 5))))

   ;; test polymorphism with keyword
   (check-ok
    (define point%
      (class object%
        #:forall X
        (super-new)
        (init-field [x : X] [y : X])))
    (new (inst point% Integer) [x 0] [y 5])
    (new (inst point% String) [x "foo"] [y "bar"]))

   ;; test polymorphism with two type parameters
   (check-ok
    (define point%
      (class object%
        #:forall (X Y)
        (super-new)
        (init-field [x : X] [y : Y])))
    (new (inst point% Integer String) [x 0] [y "foo"])
    (new (inst point% String Integer) [x "foo"] [y 3]))

   ;; test class polymorphism with method
   (check-ok
    (define id%
      (class object%
        #:forall (X)
        (super-new)
        (: m (X -> X))
        (define/public (m x) x)))
    (send (new (inst id% Integer)) m 0))

   ;; fails because m is not parametric
   (check-err #:exn #rx"Expected X.*, but got String"
    (class object%
      #:forall (X)
      (super-new)
      (: m (X -> X))
      (define/public (m x) (string-append x))))

   ;; fails because default init value cannot be polymorphic
   (check-err #:exn #rx"Default init value has wrong type"
    (class object%
      #:forall Z
      (super-new)
      (init-field [x : Z] [y : Z 0])))

   ;; fails because default field value cannot be polymorphic
   (check-err #:exn #rx"Expected Z.*, but got Zero"
    (class object%
      #:forall Z
      (super-new)
      (field [x : Z 0])))

   ;; test in-clause type annotations (next several tests)
   (check-ok
    (define c%
      (class object%
        (super-new)
        (field [x : Integer 0])))
    (+ 1 (get-field x (new c%))))

   (check-ok
    (define c%
      (class object%
        (super-new)
        (init-field [x : Integer])))
    (+ 1 (get-field x (new c% [x 5]))))

   (check-ok
    (define c%
      (class object%
        (super-new)
        (public [m : (Integer -> Integer)])
        (define (m x) (* x 2))))
    (send (new c%) m 52))

   (check-ok
    (define c%
      (class object%
        (super-new)
        (private [m : (Integer -> Integer)])
        (define (m x) (* x 2)))))

   (check-ok
    (define c%
      (class object%
        (super-new)
        (field [(x y) : Integer 0])))
    (+ 1 (get-field y (new c%))))

   ;; fails, duplicate type annotation
   (check-err #:exn #rx"Duplicate type annotation of Real"
     (class object%
       (super-new)
       (: x Real)
       (field [x : Integer 0])))

   ;; fails, expected type and annotation don't match
   (check-err #:exn #rx"Expected \\(Class \\(field \\(x String"
     (: c% (Class (field [x String])))
     (define c%
       (class object% (super-new)
         (field [x : Integer 5]))))

   ;; fails, but make sure it's not an internal error
   (check-err #:exn #rx"Cannot apply expression of type Any"
     (class object% (super-new)
            (define/pubment (foo x) 0)
            (define/public (g x) (foo 3))))

   ;; check that resolve is called appropriately for
   ;; uses of `get-field`
   (check-ok
    (define-type Foo% (Class (init-field [f (Instance Bar%)])))
    (define-type Bar% (Class (field [f Integer]) [m (Foo% -> Void)]))
    (: foo% Foo%)
    (define foo%
      (class object%
        (super-new)
        (init-field f)))
    (: bar% Bar%)
    (define bar%
      (class object%
        (super-new)
        (field [f 0])
        (define/public (m x) (void))))
    (get-field f (get-field f (new foo% [f (new bar%)]))))

   ;; check use of set-field!
   (check-ok
    (set-field! x
                (new (class object%
                       (super-new)
                       (field [x : String "foo"])))
                "bar"))

   ;; fails, check set-field! type error
   (check-err #:exn #rx"field mutation only allowed with"
    (set-field! x
                (new (class object%
                       (super-new)
                       (field [x : String "foo"])))
                2))

   ;; test occurrence typing for private fields
   (check-ok
    (class object%
      (super-new)
      (: x (U Integer String))
      (define x 3)
      (if (integer? x) (add1 x) 0))
    (class object%
      (super-new)
      (: x (Pairof (U Integer String) String))
      (define x (cons 1 "foo"))
      (if (integer? (car x)) (add1 (car x)) 0))
    (class object%
      (super-new)
      (: x Void)
      (define x (void))
      (: y (U Integer String))
      (define y "foo")
      (if (string? y) (string-append y "bar") ""))
    (class object%
      (super-new)
      (: x (U #f Number))
      (define x 3)
      (when x (add1 x))))

   ;; fails, ensure that the error mentions that the method
   ;; is given a bad method type
   (check-err #:exn #rx"not a valid method type"
    (class object%
      (super-new)
      (: home-region Any)
      (define home-reg #f)
      (public* [home-region (lambda () #f)])))

   ;; fails, ensure error mentions `super-make-object`
   (check-err #:exn #rx"super-make-object: positional"
    (class object% (super-make-object)))

   ;; check that case-lambda methods work
   (check-ok
    (define c%
      (class object%
        (super-new)
        (: m (case-> (Any -> Void)))
        (public m)
        (define m (case-lambda [(x) (void)]))))
    (send (new c%) m 'anything))

   ;; fails, test that case-lambda bodies are checked
   (check-err #:exn #rx"Expected Integer, but got String"
    (class object%
      (super-new)
      (: m (case-> (Any -> Integer)))
      (public m)
      (define m (case-lambda [(x) "bad"]))))))

(define-go class-tests)

(module+ main
  (require rackunit/text-ui)
  (run-tests (class-tests)))

