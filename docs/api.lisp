(ql:quickload "cl-d-api")

(defparameter *document-packages*
  (list "TEMPERANCE"))

(defparameter *output-path*
  #p"docs/03-reference.markdown" )

(defparameter *header*
  "The following is a list of all user-facing parts of Temperance.

If there are backwards-incompatible changes to anything listed here, they will
be noted in the changelog and the author will feel bad.

Anything not listed here is subject to change at any time with no warning, so
don't touch it.

")

(d-api:generate-documentation
  :temperance
  *output-path*
  *document-packages*
  *header*)
