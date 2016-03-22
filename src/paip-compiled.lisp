(in-package #:bones.paip)

;;;; Utils
(defun find-all (item sequence
                      &rest keyword-args
                      &key (test #'eql) test-not &allow-other-keys)
  "Find all elements of the sequence that match the item.

  Does not alter the sequence.

  "
  (if test-not
    (apply #'remove
           item sequence :test-not (complement test-not)
           keyword-args)
    (apply #'remove
           item sequence :test (complement test)
           keyword-args)))

(defun interned-symbol (&rest args)
  (intern (format nil "~{~A~}" args)))

(defun new-symbol (&rest args)
  (make-symbol (format nil "~{~A~}" args)))

(defun find-if-anywhere (test expr)
  (cond ((funcall test expr) t)
        ((consp expr) (or (find-if-anywhere test (car expr))
                          (find-if-anywhere test (cdr expr))))
        (t nil)))


;;;; UNIFICATION --------------------------------------------------------------
;;;; Variables
(define-constant unbound "Unbound"
  :test #'equal
  :documentation "A magic constant representing an unbound variable.")

(defvar *var-counter* 0
  "The number of variables created so far.")

(defstruct (var (:constructor ? ())
                (:print-function print-var))
  (name (incf *var-counter*)) ; The variable's name (defaults to a new number)
  (binding unbound)) ; The variable's binding (defaults to unbound)

(defun* print-var ((var var) stream depth)
  (if (or (and (numberp *print-level*)
               (>= depth *print-level*))
          (var-p (deref var)))
    (format stream "?~A" (var-name var))
    (write var :stream stream)))

(defun* bound-p ((var var))
  (:returns boolean)
  "Return whether the given variable has been bound."
  (not (eq (var-binding var) unbound)))

(defmacro deref (expr)
  "Chase all the bindings for the given expression in place."
  `(progn
    (loop :while (and (var-p ,expr) (bound-p ,expr))
          :do (setf ,expr (var-binding ,expr)))
    ,expr))


;;;; Bindings
(defvar *trail* (make-array 200 :fill-pointer 0 :adjustable t)
  "The trail of variable bindings performed so far.")

(defun* set-binding! ((var var) value)
  (:returns (eql t))
  "Set `var`'s binding to `value` after saving it in the trail.

  Always returns `t` (success).

  "
  (when (not (eq var value))
    (vector-push-extend var *trail*)
    (setf (var-binding var) value))
  t)

(defun* undo-bindings! ((old-trail integer))
  (:returns :void)
  "Undo all bindings back to a given point in the trail.

  The point is specified by giving the desired fill pointer.

  "
  (loop :until (= (fill-pointer *trail*) old-trail)
        :do (setf (var-binding (vector-pop *trail*)) unbound))
  (values))


;;;; Unification
(defun* unify! (x y)
  (:returns boolean)
  "Destructively unify two expressions, returning whether it was successful.

  Any variables in `x` and `y` may have their bindings set.

  "
  (cond
    ;; If they're identical objects (taking bindings into account), they unify.
    ((eql (deref x) (deref y)) t)

    ;; If they're not identical, but one is a variable, bind it to the other.
    ((var-p x) (set-binding! x y))
    ((var-p y) (set-binding! y x))

    ;; If they're both non-empty lists, unify the cars and cdrs.
    ((and (consp x) (consp y))
     (and (unify! (first x) (first y))
          (unify! (rest x) (rest y))))

    ;; Otherwise they don't unify.
    (t nil)))


;;;; COMPILATION --------------------------------------------------------------
(deftype relation ()
  'list)

(deftype clause ()
  '(trivial-types:proper-list relation))

(deftype non-negative-integer ()
  '(integer 0))


(defun prolog-compile (symbol &optional (clauses (get-clauses symbol)))
  "Compile a symbol; make a separate function for each arity."
  (when (not (null clauses))
    (let* ((arity (relation-arity (clause-head (first clauses))))
           (matching-arity-clauses (clauses-with-arity clauses #'= arity))
           (other-arity-clauses (clauses-with-arity clauses #'/= arity)))
      (compile-predicate symbol arity matching-arity-clauses)
      (prolog-compile symbol other-arity-clauses))))

(defun* clauses-with-arity
    ((clauses (trivial-types:proper-list clause))
     (test function)
     (arity non-negative-integer))
  "Return all clauses whose heads have the given arity."
  (find-all arity clauses
            :key #'(lambda (clause)
                    (relation-arity (clause-head clause)))
            :test test))


(defun* relation-arity ((relation relation))
  (:returns non-negative-integer)
  "Return the number of arguments of the given relation.

  For example: `(relation-arity '(likes sally cats))` => `2`

  "
  (length (relation-arguments relation)))

(defun* relation-arguments ((relation relation))
  (:returns list)
  "Return the arguments of the given relation.

  For example:

    * (relation-arguments '(likes sally cats))
    (sally cats)

  "
  (rest relation))


(defun* compile-predicate
    ((symbol symbol)
     (arity non-negative-integer)
     (clauses (trivial-types:proper-list clause)))
  "Compile all the clauses for the symbol+arity into a single Lisp function."
  (let ((predicate (make-predicate symbol arity))
        (parameters (make-parameters arity)))
    (compile
      (eval
        `(defun ,predicate (,@parameters continuation)
          .,(maybe-add-undo-bindings
              (mapcar #'(lambda (clause)
                         (compile-clause parameters clause 'continuation))
                      clauses)))))))

(defun* make-parameters ((arity non-negative-integer))
  (:returns (trivial-types:proper-list symbol))
  "Return the list (?arg1 ?arg2 ... ?argN)."
  (loop :for i :from 1 :to arity
        :collect (new-symbol '?arg i)))

(defun* make-predicate ((symbol symbol)
                        (arity non-negative-integer))
  (:returns symbol)
  "Returns (and interns) the symbol with the Prolog-style name symbol/arity."
  (values (interned-symbol symbol '/ arity)))


(defun make-= (x y)
  `(= ,x ,y))

(defun compile-clause (parameters clause continuation)
  "Transform away the head and compile the resulting body."
  (bind-unbound-vars
    parameters
    (compile-body
      (nconc
        (mapcar #'make-= parameters (relation-arguments (clause-head clause)))
        (clause-body clause))
      continuation)))

(defun compile-body (body continuation)
  "Compile the body of a clause."
  (if (null body)
    `(funcall ,continuation)
    (let* ((goal (first body))
           (macro (prolog-compiler-macro (predicate goal)))
           (macro-val (when macro
                        (funcall macro goal (rest body) continuation))))
      (if (and macro (not (eq macro-val :pass)))
        macro-val
        (compile-call
          (make-predicate (predicate goal)
                          (relation-arity goal))
          (mapcar #'(lambda (arg) (compile-arg arg))
                  (relation-arguments goal))
          (if (null (rest body))
            continuation
            `#'(lambda ()
                 ,(compile-body (rest body) continuation))))))))

(defun compile-call (predicate args continuation)
  `(,predicate ,@args ,continuation))

(defun prolog-compiler-macro (name)
  "Fetch the compiler macro for a Prolog predicate."
  (get name 'prolog-compiler-macro))

(defmacro def-prolog-compiler-macro (name arglist &body body)
  "Define a compiler macro for Prolog."
  `(setf (get ',name 'prolog-compiler-macro)
         #'(lambda ,arglist .,body)))

(def-prolog-compiler-macro
  = (goal body continuation)
  (let ((args (relation-arguments goal)))
    (if (/= (length args) 2)
      :pass
      `(when ,(compile-unify (first args) (second args))
         ,(compile-body body continuation)))))

(defun compile-unify (x y)
  "Return code that tests if the items unify."
  `(unify! ,(compile-arg x) ,(compile-arg y)))


(defun compile-arg (arg)
  "Generate code for an argument to a goal in the body."
  (cond ((variable-p arg) arg)
        ((not (has-variable-p arg)) `',arg)
        ((proper-list-p arg)
         `(list .,(mapcar #'compile-arg arg)))
        (t `(cons ,(compile-arg (first arg))
                  ,(compile-arg (rest arg))))))

(defun has-variable-p (x)
  "Is there a variable anywhere in the expression x?"
  (find-if-anywhere #'variable-p x))

(defun proper-list-p (x)
  "Is x a proper (non-dotted) list?"
  (or (null x)
      (and (consp x) (proper-list-p (rest x)))))


(defun maybe-add-undo-bindings (compiled-expressions)
  "Undo any bindings that need undoing.

  If there ARE any, also bind the trail before we start.

  "
  (if (= (length compiled-expressions) 1)
    compiled-expressions
    `((let ((old-trail (fill-pointer *trail*)))
        ,(first compiled-expressions)
        ,@(loop :for expression :in (rest compiled-expressions)
                :collect '(undo-bindings! old-trail)
                :collect expression)))))

(defun bind-unbound-vars (parameters expr)
  "Bind any variables in expr (besides the parameters) to new vars."
  (let ((expr-vars (set-difference (variables-in expr) parameters)))
    (if expr-vars
      `(let ,(mapcar #'(lambda (var) `(,var (?)))
                     expr-vars)
         ,expr)
      expr)))
