(in-package :postmodern)

(defclass pooled-database-connection (database-connection)
  ((pool-type :initarg :pool-type :accessor connection-pool-type))
  (:documentation "Type for database connections that are pooled.
Stores the arguments used to create it, so different pools can be
distinguished."))

(defparameter *database* nil
  "Special holding the current database. Most functions and macros
operating on a database assume this contains a connected database.")

(defun connect (database user password host &key (port 5432) pooled-p)
  "Create and return a database connection."
  (cond (pooled-p
         (let ((type (list database user password host port)))
           (or (get-from-pool type)
               (let ((connection (open-database database user password host port)))
                 (change-class connection 'pooled-database-connection :pool-type type)
                 connection))))
        (t (open-database database user password host port))))

(defun connected-p (database)
  "Test whether a database connection is still connected."
  (database-open-p database))

(defun connect-toplevel (database user password host &key (port 5432))
  "Set *database* to a new connection. Use this if you only need one
connection, or if you want a connection for debugging from the REPL."
  (when (and *database* (connected-p *database*))
    (restart-case (error "Top-level database already connected.")
      (replace () :report "Replace it with a new connection." (disconnect-toplevel))
      (leave () :report "Leave it." (return-from connect-toplevel nil))))
  (setf *database* (connect database user password host :port port))
  (values))

(defgeneric disconnect (database)
  (:method ((connection database-connection))
    (close-database connection))
  (:method ((connection pooled-database-connection))
    (add-to-pool connection))
  (:documentation "Close a database connection. Returns it to a pool
if it is a pooled connection."))

(defgeneric reconnect (database)
  (:method ((database database-connection))
    (reopen-database database))
  (:method ((connection pooled-database-connection))
    (error "Can not reconnect a pooled database."))
  (:documentation "Reconnect a database connection."))

(defun disconnect-toplevel ()
  "Disconnect *database*."
  (when (and *database* (connected-p *database*))
    (disconnect *database*))
  (setf *database* nil))

(defmacro with-connection ((database user password host &key (port 5432) pooled-p) &body body)
  "Binds *database* to a new connection and runs body in that scope."
  `(let ((*database* (connect ,database ,user ,password ,host :port ,port :pooled-p ,pooled-p)))
    (unwind-protect (progn ,@body)
      (disconnect *database*))))

(defparameter *connection-pools* (make-hash-table :test 'equal)
  "Maps pool specifiers to lists of pooled connections.")

(defparameter *pool-lock*
  (if *threads*
      (funcall (intern "MAKE-LOCK" :bordeaux-threads) "connection-pool-lock")
      nil)
  "A lock to prevent multiple threads from messing with the connection
pool at the same time. Or nil when no threads support is required.")

(defmacro with-pool-lock (&body body)
  "Aquire a lock for the pool when evaluating body \(if thread support
is present)."
  (if *threads*
      `(,(intern "WITH-LOCK-HELD" :bordeaux-threads) (*pool-lock*) ,@body)
      `(progn ,@body)))

(defun get-from-pool (type)
  "Get a database connection from the specified pool, returns nil if
no connection was available."
  (with-pool-lock
    (pop (gethash type *connection-pools*))))

(defun add-to-pool (connection)
  "Add a connection to the corresponding pool."
  (with-pool-lock
    (push connection (gethash (connection-pool-type connection) *connection-pools*)))
  (values))

(defun clear-connection-pool ()
  "Disconnect and remove all connections in the connection pool."
  (with-pool-lock
    (maphash
     (lambda (type connections)
       (declare (ignore type))
       (dolist (conn connections)
         (close-database conn)))
     *connection-pools*)
    (setf *connection-pools* (make-hash-table :test 'equal))
    (values)))

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