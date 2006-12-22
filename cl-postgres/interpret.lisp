(in-package :cl-postgres)

(defparameter *timestamp-format* :unbound
  "This is used to communicate the format \(integer or float) used for
timestamps and intervals in the current connection, so that the
interpreters for those types know how to parse them.")

(defparameter *known-types* (make-hash-table)
  "Mapping of OIDs to interpreter functions.")

(defun type-interpreter (oid)
  (gethash oid *known-types*))

(defun interpret-unknown (stream size)
  "This interpreter is used for types that we have no specific
interpreter for -- it just reads the value as a string. \(We make sure
values of unknown types are passed in text form.)"
  (#.*read-string* stream :byte-length size))

(defmacro define-interpreter (oid name fields &body value)
  "A slightly convoluted macro for defining interpreter functions and
storing them in *known-types*. It allows two forms. The first is to
pass a single type identifier after the type name, in that case a
value of this type will be read and returned directly. The second is
to pass a list of lists containing names and types, and then a body.
In this case the names will be bound to values read from the socked
and interpreted as the given types, and then the body will be run in
the resulting environment. If the last field is of type bytes, string,
or uint2s, all remaining data will be read and interpreted as an array
of the given type."
  (declare (ignore name))
  (let ((stream-name (gensym))
        (size-name (gensym))
        (length-used 0))
    (flet ((read-type (type &optional modifier)
             (case type
               (bytes `(read-bytes ,stream-name (- ,size-name ,length-used)))
               (string `(#.*read-string* ,stream-name :byte-length (- ,size-name ,length-used)))
               (uint2s `(let* ((size (/ (- ,size-name ,length-used) 2))
                               (result (make-array size :element-type '(unsigned-byte 16))))
                         (dotimes (i size)
                           (setf (elt result i) (read-uint2 ,stream-name)))
                         result))
               (int (assert (integerp modifier))
                    (incf length-used modifier)
                    `(,(integer-reader-name modifier t) ,stream-name))
               (uint (assert (integerp modifier))
                     (incf length-used modifier)
                     `(,(integer-reader-name modifier nil) ,stream-name)))))
      `(setf (gethash ,oid *known-types*)
        (lambda (,stream-name ,size-name)
          (declare (type stream ,stream-name)
                   (type integer ,size-name)
                   (ignorable ,size-name))
          ,(if (consp fields)
               `(let ,(loop :for field :in fields
                            :collect `(,(first field) ,(apply #'read-type (cdr field))))
                 ,@value)
               (read-type fields (car value))))))))

(define-interpreter 18 "char" int 1)
(define-interpreter 21 "int2" int 2)
(define-interpreter 23 "int4" int 4)
(define-interpreter 20 "int8" int 8)

(define-interpreter 16 "bool" ((value int 1))
  (if (zerop value) nil t))

(define-interpreter 17 "bytea" bytes)
(define-interpreter 25 "text" string)
(define-interpreter 1042 "bpchar" string)
(define-interpreter 1043 "varchar" string)

(define-interpreter 700 "float4" ((bits uint 4))
  (ieee-floats:decode-float32 bits))
(define-interpreter 701 "float8" ((bits uint 8))
  (ieee-floats:decode-float64 bits))

;; Numeric types are rather involved. I got some clues on their
;; structure from http://archives.postgresql.org/pgsql-interfaces/2004-08/msg00000.php
(define-interpreter 1700 "numeric"
    ((length uint 2)
     (weight int 2)
     (sign int 2)
     (dscale int 2)
     (digits uint2s))
  (declare (ignore dscale))
  (let ((total (loop :for i :from (1- length) :downto 0
                     :for scale = 1 :then (* scale #.(expt 10 4))
                     :summing (* scale (elt digits i))))
        (scale (- length weight 1)))
    (unless (zerop sign)
      (setf total (- total)))
    (/ total (expt 10000 scale))))

;; Postgresql days are measured from 01-01-2000, whereas simple-date
;; uses 01-03-2000.
(defconstant +postgres-day-offset+ -60)
(defconstant +millisecs-in-day+ (* 1000 3600 24))

(define-interpreter 1082 "date"
    ((days int 4))
  (make-instance 'date :days (+ days +postgres-day-offset+)))

(defun interpret-millisecs (bits)
  "Decode a 64 bit time-related value based on the timestamp format
used. Correct for sign bit when using integer format."
  (case *timestamp-format*
    (:float (round (* (ieee-floats:decode-float64 bits) 1000)))
    (:integer (round (if (logbitp 63 bits)
                         (dpb bits (byte 63 0) -1)
                         bits)
                     1000))))

(define-interpreter 1114 "timestamp"
    ((bits uint 8))
  (multiple-value-bind (days millisecs)
      (floor (interpret-millisecs bits) +millisecs-in-day+)
    (make-instance 'timestamp :days (+ days +postgres-day-offset+)
                   :ms millisecs)))

(define-interpreter 1186 "interval"
    ((ms uint 8)
     (days int 4)
     (months int 4))
  (make-instance 'interval :months months
                 :ms (+ (* days +millisecs-in-day+)
                        (interpret-millisecs ms))))

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