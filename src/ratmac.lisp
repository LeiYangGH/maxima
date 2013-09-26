;;; -*-  Mode: Lisp; Package: Maxima; Syntax: Common-Lisp; Base: 10 -*- ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     The data in this file contains enhancments.                    ;;;;;
;;;                                                                    ;;;;;
;;;  Copyright (c) 1984,1987 by William Schelter,University of Texas   ;;;;;
;;;     All rights reserved                                            ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     (c) Copyright 1980 Massachusetts Institute of Technology         ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :maxima)

(macsyma-module ratmac macro)

;; Polynomials are stored in the following format:
;;
;; A polynomial in a single variable is stored as a sparse list of coefficients,
;; whose first element is the polynomial's variable. The rest of the elements
;; form a plist with keys the powers (in descending order) and values the
;; coefficients.
;;
;; For example, 42*x^2 + 1 might be stored as ($x 2 42 0 1). If, say,
;; x*sin(x)+x^2 is respresented as a polynomial in x, we might expect it to come
;; out as something like
;;
;;    ($x 2 1 1 ((%sin) $x)),
;;
;; but to make it easier to work with polynomials we don't allow arbitrary
;; conses as coefficients. What actually happens is that the expression is
;; thought of as a polynomial in two variables x and "sin(x)". More on that
;; below.
;;
;; Multivariate polynomials are stored in basically the same way as single
;; variable polynomials, using the observation that a polynomial in X and Y with
;; coefficients in K is the same as a polynomial in X with coefficients in K[Y].
;;
;; Specifically, the coefficient terms can be polynomials themselves (in other
;; variables). So x^2 + x*y could be rperesented as (($x 2 1 1 ($y 1 1))) or
;; alternatively as (($y 1 ($x 1 1) 0 ($x 2 1))), depending on whether x or y
;; was taken as the primary variable.
;;
;; In the x*sin(x) + x^2 example above, the expression can be represented as
;; something like ($x 2 1 1 (sinx 1 1)). When passed around as expressions
;; outside of the core rational function code, polynomials come with some header
;; information that explains what the variables are. In this case, it would be
;; responsible for remembering that "sinx" means sin(x).
;;
;; As a slightly special case, a polynomial can also be an atom, in which case
;; it is treated as a degree zero polynomial in no particular variable. Test for
;; this using the pcoefp macro defined below.
;;
;; There are accessor macros for the parts of a polynomial defined below: p-var,
;; p-terms, p-lc, p-le and p-red (which extract the primary variable, the list
;; of powers and coefficients, the leading coefficient, the leading exponent and
;; the list of powers and coefficients except the leading coefficient,
;; respectively).
;;
;; This format is also documented in the "Introduction to Polynomials" page of
;; the manual.

;; Macros for manipulating rational functions.

(defmacro pcoefp (e) `(atom ,e))

(declaim (inline pzerop))
(defun pzerop (x)
  (if (fixnump x)
      (zerop (the fixnum x))
      (if (consp x)
	  nil
	  (and (floatp x) (zerop x)))))

(defmacro pzero () 0)
(defmacro ptzerop (terms) `(null ,terms)) ;for poly terms
(defmacro ptzero () '())

(defmacro czerop (c) `(pzerop ,c))

(defmacro cminus (c) `(- ,c))
(defmacro cminusp (c) `(minusp ,c))

;; the rational function package uses GENSYM's to represent variables.
;; The PDP-10 implementation used to use the PRINTNAME of the gensym
;; as a place to store a VALUE. Somebody changed this to value-cell instead,
;; even though using the value-cell costs more. Anyway, in NIL I want it
;; to use the property list, as thats a lot cheaper than creating a value
;; cell. Actually, better to use the PACKAGE slot, a kludge is a kludge right?

(defmacro valget (item)
  `(symbol-value ,item))

(defmacro valput (item val)
  `(setf (symbol-value ,item) ,val))

;; A historical note from Richard Fateman, on the maxima list,
;; 2006/03/17:
;;
;; "The name pointerp comes from the original hack when we wanted a
;; bunch of atoms that could be ordered fast, we just generated, say,
;; 10 gensyms.  Then we sorted them by the addresses of the symbols in
;; memory.  Then we associated them with x,y,z,....  This meant that
;; pointergp was one or two instructions on a PDP-10, in assembler."
;;
;; "That version of pointergp turned out to be more trouble than it was
;; worth because we sometimes had to interpolate between two gensym
;; "addresses" and to do that we had to kind of renumber too much of
;; the universe.  Or maybe we just weren't clever enough to do it
;; without introducing bugs."
;;
;; Richard Fateman also says pointergp needs to be fast because it's
;; called a lot.  So if you get an error from pointergp, it's probably
;; because someone forgot to initialize things correctly.

(declaim (inline pointergp))
(defun pointergp (a b)
  (> (symbol-value a) (symbol-value b)))

;;(macro ALGV (L) `(AND $ALGEBRAIC (GET ,(CADR L) 'TELLRAT)))
(defmacro algv (v)
  `(and $algebraic (get ,v 'tellrat)))


(defmacro eqn (&rest l) `(equal . ,l))

(defmacro rzero () ''(0 . 1))
(defmacro rzerop (a) `(pzerop (car ,a)))

(defmacro primpart (p) `(cadr (oldcontent ,p)))

;;poly constructor

(defmacro make-poly (var &optional (terms-or-e nil options?) (c nil e-c?) (terms nil terms?))
  (cond ((null options?) `(cons ,var '(1 1)))
	((null e-c?) `(psimp ,var ,terms-or-e))
	((null terms?) `(list ,var ,terms-or-e ,c))
	(t `(psimp ,var (list* ,terms-or-e ,c ,terms)))))

;;Poly selector functions

(defmacro p-var (p) `(car ,p))

(defmacro p-terms (p) `(cdr ,p))

(defmacro p-lc (p) `(caddr ,p))		;leading coefficient

(defmacro p-le (p) `(cadr ,p))

(defmacro p-red (p) `(cdddr ,p))

;;poly terms selectors

(defmacro pt-lc (terms) `(cadr ,terms))

(defmacro pt-le (terms) `(car ,terms))

(defmacro pt-red (terms) `(cddr ,terms))

;; Taken from SININT and RISCH.  Somebody document these please.

(defmacro r+ (r . l)
  (cond ((null l) r)
	(t `(ratpl ,r (r+ ,@l)))))

(defmacro r* (r . l)
  (cond ((null l) r)
	(t `(ratti ,r (r* ,@l) t))))

(defmacro r- (r . l)
  (cond ((null l) `(ratminus (ratfix ,r)))
	(t `(ratdif (ratfix ,r) (r+ ,@l)))))
