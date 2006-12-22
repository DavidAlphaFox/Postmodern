(defpackage :postmodern
  (:use :common-lisp :s-sql :cl-postgres :simple-date)
  (:nicknames :pomo)
  (:export 
   :connect :disconnect :reconnect :with-connection
   :*database* :connected-p :database-connection
   :connect-toplevel :disconnect-toplevel
   :clear-connection-pool
   :query :execute :doquery
   :prepare :defprepared
   :sequence-next :list-sequences :sequence-exists-p
   :list-tables :table-exists-p :table-description
   :list-views :view-exists-p
   :begin-transaction :commit-transaction :abort-transaction
   :with-transaction
   :deftable :get-id :next-id :db-null
   :dao-exists-p :query-dao :select-dao :get-dao
   :save-dao :insert-dao :update-dao :delete-dao
   :create-table :drop-table :reset-table
   :create-template :clear-template

   ;; Reduced S-SQL interface
   :sql :sql-compile
   :smallint :bigint :numeric :real :double-precision
   :bytea :text :varchar
   :*escape-sql-names-p* :sql-escape-string

   ;; Condition type from cl-postgres
   :database-error :database-error-message :database-error-code
   :database-error-detail :database-error-query

   ;; Full simple-date interface
   :date :encode-date :decode-date :day-of-week
   :timestamp :encode-timestamp :decode-timestamp
   :timestamp-to-universal-time :universal-time-to-timestamp
   :interval :encode-interval :decode-interval
   :time-add :time-subtract
   :time= :time> :time< :time<= :time>=))

(in-package :postmodern)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; Check for thread support, the authoritative setting comes from
  ;; the system definition now (so it can conditionally include
  ;; :bordeaux-threads), but if you are not using ASDF you'll have to
  ;; set it in another way.
  (defparameter *threads* postmodern-system:*threads*))

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