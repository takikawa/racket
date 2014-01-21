#lang scribble/manual

@begin[(require "../utils.rkt" scribble/eval racket/sandbox)
       (require (for-label (only-meta-in 0 [except-in typed/racket for])))]

@(define the-eval (make-base-eval))
@(the-eval '(require (except-in typed/racket #%top-interaction #%module-begin)))
@(define the-top-eval (make-base-eval))
@(the-top-eval '(require (except-in typed/racket #%module-begin)))

@(define-syntax-rule (ex . args)
   (examples #:eval the-top-eval . args))

@title{Typed Classes}

Typed Racket provides support for object-oriented programming with
the classes and objects provided by the @racketmodname[racket/class]
library.

@defform[#:literals (init field augment)
         (Class class-type-clause ...)
         #:grammar ([class-type-clause name+type
                                       (init init-type ...)
                                       (field name+type ...)
                                       (augment name+type ...)
                                       (code:line #:implements type-alias-id)
                                       (code:line #:row-var row-var-id)]
                    [init-type name+type
                               [id type #:optional]]
                    [name+type [id type]])]{
  The type of a class with the given initialization argument, method, and
  field types.

  The types of methods are provided either without a keyword, in which case
  they correspond to public methods, or with the @racketidfont{augment}
  keyword, in which case they correspond to a method that can be augmented.

  An initialization argument type specifies a name and type and optionally
  a @racket[#:optional] keyword. An initialization argument type with
  @racket[#:optional] corresponds to an argument that does not need to
  be provided at object instantiation.

  When @racket[type-alias-id] is provided, the resulting class type
  includes all of the initialization argument, method, and field types
  from the specified type alias (which must be an alias for a class type).
  Multiple @racket[#:implements] clauses may be provided for a single class
  type.

  @ex[
    (define-type Point<%> (Class (field [x Real] [y Real])))
    (: colored-point% (Class #:implements Point<%>
                             (field [color String])))
  ]

  When @racket[row-var-id] is provided, the class type is an abstract type
  that is row polymorphic. A row polymorphic class type can be instantiated
  at a specific row using @racket[inst]. Only a single @racket[#:row-var]
  clause may appear in a class type.
}

@defidform[ClassTop]{
  The supertype of all class types. A value of this type
  cannot be used for subclassing, object creation, or most
  other class functions. Its primary use is for reflective
  operations such as @racket[is-a?].
}

@defform[#:literals (field)
         (Object object-type-clause ...)
         #:grammar ([object-type-clause name+type
                                        (field name+type ...)])]{
  The type of an object with the given field and method types.

  @ex[
    (new object%)
    (new (class object% (super-new) (field [x : Real 0])))
  ]
}

@defform[(Instance class-type-expr)]{
  The type of an object that corresponds to @racket[class-type-expr].

  This is the same as an @racket[Object] type that has all of the
  method and field types from @racket[class-type-expr]. The types for
  the @racketidfont{augment} and @racketidfont{init} clauses in the
  class type are ignored.
}

@;; This uses a trick to link to racket/class's class identifier
@;; in certain cases rather than the class defined here
@(module id-holder racket/base
   (require scribble/manual (for-label racket/class))
   (provide class-element)
   (define class-element (racket class)))
@(require 'id-holder)

@defform[#:literals (inspect init init-field field inherit-field
                     public pubment override augment private inherit
                     begin)
         (class superclass-expr
           maybe-type-parameters
           class-clause ...)
         #:grammar ([class-clause (inspect inspector-expr)
                                  (init init-decl ...)
                                  (init-field init-decl ...)
                                  (field field-decl ...)
                                  (inherit-field field-decl ...)
                                  (public maybe-renamed/type ...)
                                  (pubment maybe-renamed/type ...)
                                  (override maybe-renamed/type ...)
                                  (augment maybe-renamed/type ...)
                                  (private id/type ...)
                                  (inherit id ...)
                                  method-definition
                                  definition
                                  expr
                                  (begin class-clause ...)]
                    [maybe-type-parameters (code:line)
                                           (code:line #:forall type-variable)
                                           (code:line #:forall (type-variable ...))]
                    [init-decl id/type
                               [renamed]
                               [renamed : type-expr]
                               [maybe-renamed default-value-expr]
                               [maybe-renamed : type-expr default-value-expr]]
                    [field-decl (maybe-renamed default-value-expr)
                                (maybe-renamed : type-expr default-value-expr)]
                    [id/type id
                             [id : type-expr]]
                    [maybe-renamed/type maybe-renamed
                                        [maybe-renamed : type-expr]]
                    [maybe-renamed id
                                   renamed]
                    [renamed (internal-id external-id)])]{
  Produces a class with type annotations that allows Typed Racket to type-check
  the methods, fields, and other clauses in the class.

  The meaning of the class clauses are the same as in the @class-element
  form from the @racketmodname[racket/class] library with the exception of
  the additional optional type annotations. Additional class clause
  forms from @class-element that are not listed in the grammar above are
  not currently supported in Typed Racket.

  @ex[
    (define fish%
      (class object%
        (init [size : Real])

        (: current-size Real)
        (define current-size size)

        (super-new)

        (: get-size (-> Real))
        (define/public (get-size)
          current-size)

        (: grow (Real -> Void))
        (define/public (grow amt)
          (set! current-size (+ amt current-size)))

        (: eat ((Object [get-size (-> Real)]) -> Void))
        (define/public (eat other-fish)
          (grow (send other-fish get-size)))))

    (define dory (new fish% [size 5.5]))
  ]

  Within a typed class form, one of the class clauses must be a call
  to @racket[super-new]. Failure to call @racket[super-new] will result in
  a type error. In addition, dynamic uses of @racket[super-new] (e.g.,
  calling it in a separate function within the dynamic extent of the
  class form's clauses) are restricted.

  @ex[
    (class object%
      (code:comment "Note the missing `super-new`")
      (init-field [x : Real 0] [y : Real 0]))
  ]

  If any identifier with an optional type annotation is left without an
  annotation, the type-checker will assume the type @racket[Any]
  (or @racket[Procedure] for methods) for that identifier.

  @ex[
    (define point%
      (class object%
        (super-new)
        (init-field x y)))
    point%
  ]

  When @racket[type-variable] is provided, the class is parameterized
  over the given type variables. These type variables are in scope inside
  the body of the class. The resulting class can be instantiated at
  particular types using @racket[inst].

  @ex[
    (define cons%
      (class object%
        #:forall (X Y)
        (super-new)
        (init-field [car : X] [cdr : Y])))
    cons%
    (new (inst cons% Integer String) [car 5] [cdr "foo"])
  ]
}

