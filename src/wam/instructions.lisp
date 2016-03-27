(in-package #:bones.wam)

;;;; Utilities
(defun* push-unbound-reference! ((wam wam))
  (:returns (values heap-cell heap-index))
  "Push a new unbound reference cell onto the heap."
  (wam-heap-push! wam (make-cell-reference (wam-heap-pointer wam))))

(defun* push-new-structure! ((wam wam))
  (:returns (values heap-cell heap-index))
  "Push a new structure cell onto the heap.

  The structure cell's value will point at the next address, so make sure you
  push something there too!

  "
  (wam-heap-push! wam (make-cell-structure (1+ (wam-heap-pointer wam)))))

(defun* push-new-functor! ((wam wam) (functor symbol) (arity arity))
  (:returns (values heap-cell heap-index))
  "Push a new functor cell onto the heap.

  If the functor isn't already in the functor table it will be added.

  "
  (wam-heap-push! wam (make-cell-functor
                        (wam-ensure-functor-index wam functor)
                        arity)))


(defun* bound-reference-p ((wam wam) (address heap-index))
  (:returns boolean)
  "Return whether the cell at `address` is a bound reference."
  (ensure-boolean
    (let ((cell (wam-heap-cell wam address)))
      (and (cell-reference-p cell)
           (not (= (cell-value cell) address))))))

(defun* unbound-reference-p ((wam wam) (address heap-index))
  (:returns boolean)
  "Return whether the cell at `address` is an unbound reference."
  (ensure-boolean
    (let ((cell (wam-heap-cell wam address)))
      (and (cell-reference-p cell)
           (= (cell-value cell) address)))))

(defun* matching-functor-p ((wam wam)
                            (cell heap-cell)
                            (functor symbol)
                            (arity arity))
  (:returns boolean)
  "Return whether `cell` is a functor cell of `functor`/`arity`."
  (ensure-boolean
    (and (cell-functor-p cell)
         (= arity (cell-functor-arity cell))
         (eql functor
              (wam-functor-lookup wam (cell-functor-index cell))))))


(defun* deref ((wam wam) (address heap-index))
  (:returns heap-index)
  "Dereference the address in the WAM to its eventual destination.

  If the address is a variable that's bound to something, that something will be
  looked up (recursively) and the address of whatever it's ultimately bound to
  will be returned.

  "
  (if (bound-reference-p wam address)
    (deref wam (cell-value (wam-heap-cell wam address)))
    address))


(defun* bind! ((wam wam) (address-1 heap-index) (address-2 heap-index))
  (:returns :void)
  "Bind the unbound reference cell to the other.

  `bind!` takes two addresses as arguments.  At least one of these *must* refer
  to an unbound reference cell.  This unbound reference will be bound to point
  at the other address.

  If both addresses refer to unbound references, the direction of the binding is
  chosen arbitrarily.

  "
  (cond
    ((unbound-reference-p wam address-1)
     (setf (wam-heap-cell wam address-1)
           (make-cell-reference address-2)))
    ((unbound-reference-p wam address-2)
     (setf (wam-heap-cell wam address-2)
           (make-cell-reference address-1)))
    (t (error "At least one cell must be an unbound reference when binding.")))
  (values))


(defun* fail! ((wam wam))
  (:returns :void)
  "Mark a failure in the WAM."
  (setf (wam-fail wam) t)
  (values))


(defun* unify ((wam wam) (a1 heap-index) (a2 heap-index))
  nil
  )


;;;; Query Instructions
(defun* %put-structure ((wam wam)
                        (functor symbol)
                        (arity arity)
                        (register register-index))
  (:returns :void)
  (setf (wam-register wam register)
        (nth-value 1 (push-new-structure! wam)))
  (push-new-functor! wam functor arity)
  (values))

(defun* %set-variable ((wam wam) (register register-index))
  (:returns :void)
  (setf (wam-register wam register)
        (nth-value 1 (push-unbound-reference! wam)))
  (values))

(defun* %set-value ((wam wam) (register register-index))
  (:returns :void)
  (wam-heap-push! wam (wam-register-cell wam register))
  (values))


;;;; Program Instructions
(defun* %get-structure ((wam wam)
                        (functor symbol)
                        (arity arity)
                        (register register-index))
  (:returns :void)
  (let* ((addr (deref wam (wam-register wam register)))
         (cell (wam-heap-cell wam addr)))
    (cond
      ;; If the register points at a reference cell, we push two new cells onto
      ;; the heap:
      ;;
      ;;     |   N | STR | N+1 |
      ;;     | N+1 | FUN | f/n |
      ;;
      ;; Then we bind this reference cell to point at the new structure and flip
      ;; over to write mode.
      ;;
      ;; It seems a bit confusing that we don't push the rest of the structure
      ;; stuff on the heap after it too.  But that's going to happen in the next
      ;; few instructions (which will be unify-*'s, executed in write mode).
      ((cell-reference-p cell)
       (let ((new-structure-address (nth-value 1 (push-new-structure! wam))))
         (push-new-functor! wam functor arity)
         (bind! wam addr new-structure-address)
         (setf (wam-mode wam) :write)))

      ;; If the register points at a structure cell, then we look at where that
      ;; cell points (which will be the functor cell for the structure):
      ;;
      ;;     |   N | STR | M   | points at the structure, not necessarily contiguous
      ;;     |       ...       |
      ;;     |   M | FUN | f/2 | the functor (hopefully it matches)
      ;;     | M+1 | ... | ... | pieces of the structure, always contiguous
      ;;     | M+2 | ... | ... | and always right after the functor
      ;;
      ;; If it matches the functor we're looking for, we can proceed.  We set
      ;; the S register to the address of the first subform we need to match
      ;; (M+1 in the example above).
      ;;
      ;; What about if it's a 0-arity functor?  The S register will be set to
      ;; garbage.  But that's okay, because we know the next thing in the stream
      ;; of instructions will be another get-structure and we'll just blow away
      ;; the S register there.
      ((cell-structure-p cell)
       (let* ((functor-addr (cell-value cell))
              (functor-cell (wam-heap-cell wam functor-addr)))
         (if (matching-functor-p wam functor-cell functor arity)
           (progn
             (setf (wam-s wam) (1+ functor-addr))
             (setf (wam-mode wam) :read))
           (fail! wam))))
      (t (fail! wam))))
  (values))

(defun* %unify-variable ((wam wam) (register register-index))
  (:returns :void)
  (ecase (wam-mode wam)
    (:read (setf (wam-register wam register)
                 (wam-s-cell wam)))
    (:write (setf (wam-register wam register)
                  (nth-value 1 (push-unbound-reference! wam)))))
  (incf (wam-s wam))
  (values))

(defun* %unify-value ((wam wam) (register register-index))
  (:returns :void)
  (ecase (wam-mode wam)
    (:read (unify wam
                  (cell-value (wam-register wam register))
                  (wam-s wam)))
    (:write (wam-heap-push! wam (wam-register wam register))))
  (incf (wam-s wam))
  (values))

