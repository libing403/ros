;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Message ops
;; Note: if using certain versions of the SLIME interface to 
;; SBCL, there are occasional errors when loading this file 
;; within SLIME if it was compiled from the command-line 
;; (or vice versa) - apparently the pprint-logical-block 
;; below compiles differently in the two cases.  This can be 
;; fixed by just touching this file, causing it to be 
;; recompiled.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package roslisp)



(defclass ros-message () ())

(defgeneric serialize (msg str)
  (:documentation "Serialize message object MSG onto stream STR."))

(defgeneric deserialize (msg str)
  (:documentation "Deserialize from stream STR into message object MSG and also returns MSG.  MSG may also be a symbol naming a message type, in which case a new object of that type is created and returned.")
  (:method ((msg symbol) str)
    (let ((m (make-instance msg)))
      (deserialize m str)
      m)))
	   

(defgeneric serialization-length (msg)
  (:documentation "Length of this message")
  (:method ((msg symbol))
    (warn "Hmm... unexpectedly asked for serialization length of ~a.  Likely an error - please inform roslisp developers." msg)
    42))

(defgeneric md5sum (msg-type)
  (:documentation "Return the md5 sum of this message type.")
  (:method ((msg-type array))
    (if (stringp msg-type)
	(md5sum (get-topic-class-name msg-type))
	(progn
	  (warn "Hmmm... unexpected topic type specifier ~a in md5sum.  Passing it on anyway..." msg-type)
	  (call-next-method)))))

(defgeneric ros-datatype (msg-type)
  (:documentation "Return the datatype given a message type, service type, service request or response type, or topic name")
  (:method ((msg-type array))
    (if (stringp msg-type)
	(ros-datatype (get-topic-class-name msg-type))
	(progn
	  (warn "Hmm... unexpected topic type specifier ~a in ros-datatype.  Passing it on anyway..." msg-type)
	  (call-next-method)))))

(defgeneric message-definition (msg-type)
  (:documentation "Return the definition of this message type")
  (:method ((msg-type array))
    (if (stringp msg-type)
	(message-definition (get-topic-class-name msg-type))
	(progn
	  (warn "Hmm... unexpected topic type specifier ~a in message-definition.  Passing it on anyway..." msg-type)
	  (call-next-method)))))


(defgeneric service-request-type (srv))
(defgeneric service-response-type (srv))
(defun make-response (service-type &rest args)
  (apply #'make-instance (service-response-type service-type) args))

(defgeneric symbol-codes (msg-type)
  (:documentation "Return an association list from symbols to numbers (the const declarations in the .msg file).")
  (:method ((msg-type symbol)) nil))


(defgeneric symbol-code (msg-type symbol)
  (:documentation "symbol-code MSG-TYPE SYMBOL.  Gets the value of a message-specific constant declared in a msg file.  The first argument is either a symbol naming the message class, or an instance of the class, and the second argument is the keyword symbol corresponding to the constant name. 

For example, to get the value of the DEBUG constant from Log.msg, use (symbol-code '<Log> :debug).")
  (:method ((m ros-message) s) (symbol-code (class-of m) s))
  (:method ((m symbol) s)
    (let ((pair (assoc s (symbol-codes m))))
      (unless pair
	(error "Could not get symbol code for ~a for ROS message type ~a" s m))
      (cdr pair))))

(defgeneric ros-message-to-list (msg)
  (:documentation "Return a structured list representation of the message.  For example, say message type foo has a float field x equal to 42, and a field y which is itself a message of type bar, which has a single field z=24.  This function would then return the structured list '(foo (:x . 42.0) (:y . (bar (:z . 24)))).  

The return value can be passed to list-to-ros-message to retrieve an equivalent message to the original.

As a base case, non-ros messages just return themselves.")
  (:method (msg)
    (check-type msg (not ros-message) "something that is not a ros-message")
    msg))


(defgeneric list-to-ros-message (l)
  (:method ((l list))
    (apply #'make-instance (first l) (mapcan #'(lambda (pair) (list (car pair) (list-to-ros-message (cdr pair)))) (rest l))))
  (:method (msg)
    msg))

(defun convert-to-keyword (s)
  (declare (symbol s))
  (if (keywordp s)
      s
      (intern (symbol-name s) 'keyword)))

(defun extract-nested-field (l f)
  "extract a field from a message that has been converted into a list.  F can also be a list.  E.g, if F is '(:foo :bar) that means extract field foo of field bar of the message."
  (cond 
    ((symbolp f) (get-field l f))
    ((null (rest f)) (get-field l (first f)))
    (t (get-field (extract-nested-field l (rest f)) (first f)))))

(defun get-field (l f)
  (let ((pair (assoc f (rest l))))
    (unless pair
      (error "Could not find field ~a in ~a" f l))
    (cdr pair)))

(defmacro with-fields (bindings m &body body)
  "with-fields BINDINGS MSG &rest BODY

A macro for convenient access to message fields.

BINDINGS is an unevaluated list of bindings.  Each binding is like a let binding (FOO BAR), where FOO is a symbol naming a variable that will be bound to the field value.  BAR describes the field.  In the simplest case it's just a symbol naming the field.  It can also be a list, e.g. (QUX GAR).  This means the field QUX of the field GAR of the message.  Finally, the entire binding can be a symbol FOO, which is a shorthand for (FOO FOO).  
MSG evaluates to a message.
BODY is the body, surrounded by an implicit progn.

As an example, instead of 
(let ((foo (pkg:foo-val (pkg:bar-val m)))
      (baz (pkg:baz-val m)))
  (stuff))

you can use
(with-fields ((foo (foo bar))
	      baz)
    (stuff))"

  (let ((msg-list (gensym)))
    `(let ((,msg-list (ros-message-to-list ,m)))
       (let 
	   ,(mapcar #'(lambda (binding)
			(when (symbolp binding) (setq binding (list binding binding)))
			(symbol-macrolet ((field (second binding)))
			  (setf field (mapcar #'convert-to-keyword (if (symbolp field) (list field) field))))
			`(,(first binding) (extract-nested-field ,msg-list ',(second binding))))
		    bindings)
	 ,@body))))


(defun read-ros-message (stream)
  (list-to-ros-message (read stream)))

(defun pprint-ros-message (&rest args &aux str m)
  (if (= (length args) 1)
      (setf str t m (first args))
      (setf str (first args) m (second args)))
  
  (pprint-logical-block (str nil :prefix "[" :suffix "]")
    (let ((l (ros-message-to-list m)))
      (write (first l) :stream str)
      (dolist (f (rest l))
	(format str "~:@_  ~a:~:@_    ~w" (car f) (cdr f)))))

)


(defun field-pair (f l)
  (let ((p (assoc (intern (symbol-name (car f)) :keyword) (cdr l))))
    (assert p nil "Couldn't find ~a in ~a" (car f) (cdr l))
    (if (cdr f)
	(field-pair (cdr f) (cdr p))
	p)))



(defun make-message-fn (msg-type &rest args)
  (destructuring-bind (pkg type) (tokens (string-upcase msg-type) :separators '(#\/))
    (let ((pkg (find-package (intern pkg 'keyword))))
      (assert pkg nil "Can't find package ~a" pkg)
      (let ((class-name (find-symbol (concatenate 'string "<" type ">") pkg)))
	(assert class-name nil "Can't find class for ~a" msg-type)
	(let ((l (ros-message-to-list (make-instance class-name))))
	  (while args
	    (let* ((field (pop args))
		   (val (pop args)))
	      (setf (cdr (field-pair (designated-list field) l)) val)))
	  (list-to-ros-message l))))))

(defmacro make-message (msg-type &rest args)
  "make-message MSG-TYPE &rest ARGS

Convenience macro for creating messages easily.

MSG-TYPE is a string naming a message ros datatype.

ARGS is a list of form FIELD-SPEC1 VAL1 ... FIELD-SPECk VALk
Each FIELD-SPEC (unevaluated) is a list (or a symbol, which designates a list of one element) that refers to a possibly nested field.
VAL is the corresponding value.

For example, if MSG-TYPE is the string robot_msgs/Pose, and ARGS are (position x) 42 (orientation w) 1
this will create a Pose with the x field of position equal to 42 and the w field of orientation equal to 1 (other fields equal their default values)."

  `(make-message-fn ,msg-type
		    ,@(loop
			 for i from 0
			 for arg in args
			 collect (if (evenp i) `',arg arg))))
			   



(set-pprint-dispatch 'ros-message #'pprint-ros-message)
