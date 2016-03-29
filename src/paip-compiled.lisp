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

(defun find-anywhere (item tree)
  "Does item occur anywhere in tree?"
  (if (atom tree)
    (if (eql item tree) tree)
    (or (find-anywhere item (first tree))
        (find-anywhere item (rest tree)))))

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
      continuation
      (mapcar #'self-cons parameters))))

(defun compile-body (body continuation bindings)
  "Compile the body of a clause."
  (if (null body)
    `(funcall ,continuation)
    (let* ((goal (first body))
           (macro (prolog-compiler-macro (predicate goal)))
           (macro-val (when macro
                        (funcall macro goal (rest body) continuation bindings))))
      (if (and macro (not (eq macro-val :pass)))
        macro-val
        (compile-call
          (make-predicate (predicate goal)
                          (relation-arity goal))
          (mapcar #'(lambda (arg) (compile-arg arg bindings))
                  (relation-arguments goal))
          (if (null (rest body))
            continuation
            `#'(lambda ()
                 ,(compile-body (rest body) continuation
                                (bind-new-variables bindings goal)))))))))

(defun bind-new-variables (bindings goal)
  "Extend bindings to include any unbound variables in goal."
  (let ((variables (remove-if #'(lambda (v) (assoc v bindings))
                              (variables-in goal))))
    (nconc (mapcar #'self-cons variables) bindings)))

(defun self-cons (x) (cons x x))

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
  = (goal body continuation bindings)
  (let ((args (relation-arguments goal)))
    (if (/= (length args) 2)
      :pass
      (multiple-value-bind (code1 bindings1)
          (compile-unify (first args) (second args) bindings)
          (compile-if code1 (compile-body body continuation bindings1))))))

(defun compile-unify (x y bindings)
  "Return 2 values: code to test if x any y unify, and a new binding list."
  (cond
    ((not (or (has-variable-p x) (has-variable-p y)))
     (values (equal x y) bindings))
    ((and (consp x) (consp y))
     (multiple-value-bind (code1 bindings1)
         (compile-unify (first x) (first y) bindings)
       (multiple-value-bind (code2 bindings2)
           (compile-unify (rest x) (rest y) bindings1)
         (values (compile-if code1 code2) bindings2))))
    ((variable-p x) (compile-unify-variable x y bindings))
    (t (compile-unify-variable y x bindings))))

(defun compile-if (pred then-part)
  (case pred
    ((t) then-part)
    ((nil) nil)
    (otherwise `(if ,pred ,then-part))))

(defun compile-unify-variable (x y bindings)
  "X is a variable, and Y might be."
  (let* ((xb (follow-binding x bindings))
         (x1 (if xb (cdr xb) x))
         (yb (if (variable-p y) (follow-binding y bindings)))
         (y1 (if yb (cdr yb) y)))
    (cond
      ((or (eq x '?) (eq y '?)) (values t bindings))
      ((not (and (equal x x1) (equal y y1)))
       (compile-unify x1 y1 bindings))
      ((find-anywhere x1 y1) (values nil bindings))
      ((consp y1)
       (values `(unify! ,x1 ,(compile-arg y1 bindings))
               (bind-variables-in y1 bindings)))
      ((not (null xb))
       (if (and (variable-p y1) (null yb))
           (values 't (extend-bindings y1 x1 bindings))
           (values `(unify! ,x1 ,(compile-arg y1 bindings))
                   (extend-bindings x1 y1 bindings))))
      ((not (null yb))
       (compile-unify-variable y1 x1 bindings))
      (t (values 't (extend-bindings x1 y1 bindings))))))

(defun bind-variables-in (exp bindings)
  "Bind all variables in exp to themselves, and add that to bindings (except for already-bound vars)."
  (dolist (var (variables-in exp))
    (when (not (get-binding var bindings))
      (setf bindings (extend-bindings var var bindings))))
  bindings)

(defun follow-binding (var bindings)
  "Get the ultimate binding of var according to the bindings."
  (let ((b (get-binding var bindings)))
    (if (eq (car b) (cdr b))
      b
      (or (follow-binding (cdr b) bindings)
          b))))

(defun compile-arg (arg bindings)
  "Generate code for an argument to a goal in the body."
  (cond ((eql arg '?) '(?))
        ((variable-p arg)
         (let ((binding (get-binding arg bindings)))
           (if (and (not (null binding))
                    (not (eq arg (binding-value binding))))
             (compile-arg (binding-value binding) bindings)
             arg)))
        ((not (has-variable-p arg)) `',arg)
        ((proper-list-p arg)
         `(list .,(mapcar #'(lambda (a) (compile-arg a bindings))
                          arg)))
        (t `(cons ,(compile-arg (first arg) bindings)
                  ,(compile-arg (rest arg) bindings)))))

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


(defmacro <- (&rest clause)
  "Add a clause to the database."
  `(add-clause ',(make-anonymous clause)))


(defun make-anonymous (exp &optional (anon-vars (anonymous-variables-in exp)))
  "Replace variables that are only used once with ?."
  (cond ((consp exp)
         (cons (make-anonymous (first exp) anon-vars)
               (make-anonymous (rest exp) anon-vars)))
        ((member exp anon-vars) '?)
        (t exp)))

(defun anonymous-variables-in (tree)
  "Return a list of all variables that appear only once in tree."
  (let ((seen-once nil)
        (seen-more nil))
    (labels ((walk (x)
               (cond
                 ((variable-p x)
                  (cond ((member x seen-once)
                         (setf seen-once (delete x seen-once))
                         (push x seen-more))
                        ((member x seen-more) nil)
                        (t (push x seen-once))))
                 ((consp x)
                  (walk (first x))
                  (walk (rest x))))))
      (walk tree)
      seen-once)))



;;;; UI -----------------------------------------------------------------------
(defvar *uncompiled* nil "Prolog symbols that have not been compiled.")

(defun add-clause (clause)
  "Add a clause to the database, indexed by the head's predicate."
  (let ((pred (predicate (clause-head clause))))
    (pushnew pred *db-predicates*)
    (pushnew pred *uncompiled*)
    (setf (get pred clause-key)
          (nconc (get-clauses pred) (list clause)))
    pred))


(defun top-level-prove (goals)
  "Prove the list of goals by compiling and calling it."
  (clear-predicate 'top-level-query)
  (let ((vars (delete '? (variables-in goals))))
    (add-clause `((top-level-query)
                  ,@goals
                  (show-prolog-vars ,(mapcar #'symbol-name vars)
                                    ,vars))))
  (run-prolog 'top-level-query/0 #'ignorelol)
  (format t "~&No.")
  (values))

(defun run-prolog (procedure continuation)
  "Run an 0-ary Prolog prodecure with the given continuation."
  (prolog-compile-symbols)
  (setf (fill-pointer *trail*) 0)
  (setf *var-counter* 0)
  (catch 'top-level-prove
         (funcall procedure continuation)))

(defun prolog-compile-symbols (&optional (symbols *uncompiled*))
  (mapc #'prolog-compile symbols)
  (setf *uncompiled* (set-difference *uncompiled* symbols)))

(defun ignorelol (&rest args)
  (declare (ignore args))
  nil)

(defun show-prolog-vars/2 (var-names vars cont)
  (if (null vars)
    (format t "~&Yes")
    (loop :for name :in var-names
          :for var :in vars :do
          (format t "~&~A = ~A" name (deref-exp var))))
  (if (continue-ask)
    (funcall cont)
    (throw 'top-level-prove nil)))

(defun deref-exp (exp)
  (if (atom (deref exp))
    exp
    (cons (deref-exp (first exp))
          (deref-exp (rest exp)))))


(defmacro ?- (&rest goals)
  `(top-level-prove ',(replace-wildcard-variables goals)))


