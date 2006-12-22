(defpackage :cl-postgres
  (:use :common-lisp :md5 :trivial-sockets :simple-date)
  (:export :database-error
           :database-error-message
           :database-error-code
           :database-error-detail
           :database-error-query
           :database-connection
           :connection-meta
           :open-database
           :reopen-database
           :database-open-p
           :close-database
           :exec-query
           :prepare-query
           :exec-prepared
           :field-name
           :field-type
           :row-reader
           :def-row-reader
           :next-row
           :next-field
           :list-row-reader
           :alist-row-reader
           :ignore-row-reader))

(in-package :cl-postgres)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Optimization settings (only used by functions that need it).
  (defparameter *optimize*
    '(optimize (speed 3) (safety 0) (space 1) (debug 1)
      (compilation-speed 0)))
  ;; Bind some variables depending on whether we are using utf-8. This
  ;; may look like a bad hack, and it probably is, but on the bright
  ;; side, the function to call for handling strings is determined at
  ;; compile-time and there is no run-time overhead.
  (cond (cl-postgres-system:*unicode*
         (defparameter *string-byte-length* (intern "UTF-8-BYTE-LENGTH" :trivial-utf-8))
         (defparameter *write-string* (intern "WRITE-UTF-8-BYTES" :trivial-utf-8))
         (defparameter *read-string* (intern "READ-UTF-8-STRING" :trivial-utf-8))
         (defparameter *string-bytes* (intern "STRING-TO-UTF-8-BYTES" :trivial-utf-8))
         (defparameter *client-encoding* "UNICODE"))
        (t
         (defparameter *string-byte-length* 'length)
         (defparameter *write-string* 'write-ascii-string)
         (defparameter *read-string* 'read-ascii-string)
         (defparameter *string-bytes* 'ascii-string-bytes)
         (defparameter *client-encoding* "SQL_ASCII"))))

;;; Copyright (c) 2006 Marijn Haverbeke
;;;
;;; This software is provided 'as-is', without any express or implied
;;; warranty. In no event will the authors be held liable for any
;;; damages arising from the use of this software.
;;;
;;; Permission is granted to anyone to use this software for any
;;; purpose, including commercial applications, and to alter it and
;;; redistribute it freely, subject to the following restrictions:
;;;
;;; 1. The origin of this software must not be misrepresented; you must
;;;    not claim that you wrote the original software. If you use this
;;;    software in a product, an acknowledgment in the product
;;;    documentation would be appreciated but is not required.
;;;
;;; 2. Altered source versions must be plainly marked as such, and must
;;;    not be misrepresented as being the original software.
;;;
;;; 3. This notice may not be removed or altered from any source
;;;    distribution.