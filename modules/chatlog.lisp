#|
  This file is a part of Colleen
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :org.tymoonnext.colleen)
(defpackage org.tymoonnext.colleen.mod.chatlog
  (:use :cl :colleen)
  (:shadowing-import-from :colleen :restart))
(in-package :org.tymoonnext.colleen.mod.chatlog)

(define-module chatlog ()
  ((%active-in :initarg :active-in :initform () :accessor active-in)
   (%db :initarg :db :accessor db)
   (%host :initarg :host :accessor host)
   (%port :initarg :port :accessor port)
   (%user :initarg :user :accessor user)
   (%pass :initarg :pass :accessor pass))
  (:documentation "Logs messages in channels to a database."))

(defmethod start ((chatlog chatlog))
  (setf (active-in chatlog) (config-tree :chatlog :active))
  (connect-db chatlog
              :db (config-tree :chatlog :db)
              :host (config-tree :chatlog :host)
              :port (config-tree :chatlog :port)
              :user (config-tree :chatlog :user)
              :pass (config-tree :chatlog :pass)))

(defmethod stop ((chatlog chatlog))
  (disconnect-db chatlog)
  (setf (config-tree :chatlog :db) (db chatlog))
  (setf (config-tree :chatlog :host) (host chatlog))
  (setf (config-tree :chatlog :port) (port chatlog))
  (setf (config-tree :chatlog :user) (user chatlog))
  (setf (config-tree :chatlog :pass) (pass chatlog))
  (setf (config-tree :chatlog :active) (active-in chatlog)))

(defmethod connect-db ((chatlog chatlog) &key (db (db chatlog)) (host (host chatlog)) (port (port chatlog)) (user (user chatlog)) (pass (pass chatlog)))
  (setf (db chatlog) db)
  (setf (host chatlog) host)
  (setf (port chatlog) port)
  (setf (user chatlog) user)
  (setf (pass chatlog) pass)
  (clsql:connect (list host db user pass port) :database-type :mysql)
  (unless (clsql:table-exists-p "chatlog")
    (clsql:create-table "chatlog" '(("server" (string 36) :not-null)
                                    ("channel" (string 36) :not-null)
                                    ("user" (string 36) :not-null)
                                    ("time" integer :not-null)
                                    ("type" (string 1) :not-null)
                                    ("message" text)))))

(defmethod disconnect-db ((chatlog chatlog))
  (clsql:disconnect))

(defconstant +UNIX-EPOCH-DIFFERENCE+ (encode-universal-time 0 0 0 1 1 1970 0))
(defmethod insert-record ((chatlog chatlog) server channel user type message)
  (when (find (format NIL "~a/~a" server channel) (active-in chatlog) :test #'string-equal)
    (clsql:insert-records :into "chatlog"
                          :av-pairs `(("server" . ,(format NIL "~a" server))
                                      ("channel" . ,channel)
                                      ("user" . ,user)
                                      ("time" . ,(- (get-universal-time) +UNIX-EPOCH-DIFFERENCE+))
                                      ("type" . ,type)
                                      ("message" . ,message)))))

(define-group chatlog chatlog :documentation "Change chatlog settings.")

(define-command (chatlog acivate) chatlog (&optional channel server) (:authorization T :documentation "Activate logging for a channel.")
  (unless channel (setf channel (channel event)))
  (unless server (setf server (name (server event))))
  (pushnew (format NIL "~a/~a" server channel) (active-in chatlog) :test #'string-equal)
  (respond event "Activated logging for ~a/~a" server channel))

(define-command (chatlog deactivate) chatlog (&optional channel server) (:authorization T :documentation "Deactivate logging for a channel.")
  (unless channel (setf channel (channel event)))
  (unless server (setf server (name (server event))))
  (setf (active-in chatlog)
        (delete (format NIL "~a/~a" server channel) (active-in chatlog) :test #'string-equal))
  (respond event "Deactivated logging for ~a/~a" server channel))

(define-command (chatlog reconnect) chatlog (&optional db host port user pass) (:authorization T :documentation "Restart connection to the database.")
  (disconnect-db chatlog)
  (connect-db chatlog 
              :db (or db (db chatlog)) 
              :host (or host (host chatlog)) 
              :port (or port (port chatlog)) 
              :user (or user (user chatlog)) 
              :pass (or pass (pass chatlog))))

(define-handler chatlog (privmsg-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "m" (message event)))

(define-handler chatlog (quit-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "q" (format NIL " ** QUIT ~a" (message event))))

(define-handler chatlog (part-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "p" " ** PART"))

(define-handler chatlog (join-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "j" " ** JOIN"))

(define-handler chatlog (mode-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "m" (format NIL " ** MODE ~a" (mode event))))

(define-handler chatlog (topic-event event)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "t" (format NIL " ** TOPIC ~a" (topic event))))