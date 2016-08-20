(defpackage #:temperance.utils
  (:use
    #:cl
    #:cl-arrows
    #:temperance.quickutils)
  (:export
    #:push-if-new
    #:recursively
    #:recur
    #:when-let
    #:megabytes
    #:ecase/tree
    #:gethash-or-init
    #:aref-or-init
    #:define-lookup
    #:queue
    #:make-queue
    #:enqueue
    #:dequeue
    #:queue-contents
    #:queue-empty-p
    #:queue-append))

(defpackage #:temperance.circle
  (:use #:cl)
  (:export
    #:circle
    #:make-circle-with
    #:make-empty-circle
    #:circle-to-list
    #:circle-prepend
    #:circle-prepend-circle
    #:circle-append
    #:circle-append-circle
    #:circle-next
    #:circle-prev
    #:circle-forward
    #:circle-backward
    #:circle-value
    #:circle-rotate
    #:circle-nth
    #:circle-insert-before
    #:circle-insert-after
    #:circle-sentinel-p
    #:circle-empty-p
    #:circle-remove
    #:circle-backward-remove
    #:circle-forward-remove
    #:circle-replace
    #:circle-backward-replace
    #:circle-forward-replace
    #:circle-splice
    #:circle-backward-splice
    #:circle-forward-splice
    #:circle-insert-beginning
    #:circle-insert-end))

(defpackage #:temperance.wam
  (:use
    #:cl
    #:cl-arrows
    #:temperance.circle
    #:temperance.quickutils
    #:temperance.utils)
  (:export
    #:make-database
    #:reset-database
    #:with-database
    #:with-fresh-database

    #:invoke-rule
    #:invoke-fact
    #:invoke-facts

    #:rule
    #:fact
    #:facts

    #:push-logic-frame
    #:pop-logic-frame
    #:finalize-logic-frame
    #:push-logic-frame-with

    #:invoke-query
    #:invoke-query-all
    #:invoke-query-map
    #:invoke-query-do
    #:invoke-query-find
    #:invoke-prove

    #:query
    #:query-all
    #:query-map
    #:query-do
    #:query-find
    #:prove

    #:call
    #:?
    #:!))

(defpackage #:temperance
  (:use #:cl #:temperance.wam)
  (:export
    #:make-database
    #:with-database
    #:with-fresh-database

    #:invoke-rule
    #:invoke-fact
    #:invoke-facts

    #:rule
    #:fact
    #:facts

    #:push-logic-frame
    #:pop-logic-frame
    #:finalize-logic-frame
    #:push-logic-frame-with

    #:invoke-query
    #:invoke-query-all
    #:invoke-query-map
    #:invoke-query-do
    #:invoke-query-find
    #:invoke-prove

    #:query
    #:query-all
    #:query-map
    #:query-do
    #:query-find
    #:prove

    #:call
    #:?
    #:!

    ))
