;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-

(in-package :it.bese.fiveam)

;;;; ** Random (QuickCheck-ish) testing

;;;; FiveAM provides the ability to automatically generate a
;;;; collection of random input data for a specific test and run a
;;;; test multiple times.

;;;; Specification testing is done through the FOR-ALL macro. This
;;;; macro will bind variables to random data and run a test body a
;;;; certain number of times. Should the test body ever signal a
;;;; failure we stop running and report what values of the variables
;;;; caused the code to fail.

;;;; The generation of the random data is done using "generator
;;;; functions" (see below for details). A generator function is a
;;;; function which creates, based on user supplied parameters, a
;;;; function which returns random data. In order to facilitate
;;;; generating good random data the FOR-ALL macro also supports guard
;;;; conditions and creating one random input based on the values of
;;;; another (see the FOR-ALL macro for details).

;;;; *** Public Interface to the Random Tester

(defparameter *num-trials* 100
  "Number of times we attempt to run the body of the FOR-ALL test.")

(defparameter *max-trials* 10000
  "Number of total times we attempt to run the body of the
  FOR-ALL test including when the body is skipped due to failed
  guard conditions.

Since we have guard conditions we may get into infinite loops where
the test code is never run due to the guards never returning
true. This second limit prevents that from happening.")

(defmacro for-all (bindings &body body)
  "Bind BINDINGS to random variables and execute BODY `*num-trials*` times.

BINDINGS::

A a list of binding forms, each element is a list of:
+
    (BINDING VALUE &optional GUARD)
+
VALUE, which is evaluated once when the for-all is evaluated, must
return a generator which be called each time BODY is
evaluated. BINDING is either a symbol or a list which will be passed
to destructuring-bind. GUARD is a form which, if present, stops BODY
from executing when it returns NIL. The GUARDS are evaluated after all
the random data has been generated and they can refer to the current
value of any binding. 
+
[NOTE]
Generator forms, unlike guard forms, can not contain references to the
bound variables.

BODY::

The code to run. Will be run `*NUM-TRIALS*` times (unless the `*MAX-TRIALS*` limit is reached).

Examples:

--------------------------------
\(for-all ((a (gen-integer)))
  (is (integerp a)))

\(for-all ((a (gen-integer) (plusp a)))
  (is (integerp a))
  (is (plusp a)))

\(for-all ((less (gen-integer))
          (more (gen-integer) (< less more)))
  (is (<= less more)))

\(defun gen-two-integers ()
  (lambda ()
    (list (funcall (gen-integer))
          (funcall (gen-integer)))))

\(for-all (((a b) (gen-two-integers)))
  (is (integerp a))
  (is (integerp b)))
--------------------------------
"
  (with-gensyms (test-lambda-args)
    `(perform-random-testing
      (list ,@(mapcar #'second bindings))
      (lambda (,test-lambda-args)
        (destructuring-bind ,(mapcar #'first bindings)
            ,test-lambda-args
          (if (and ,@(delete-if #'null (mapcar #'third bindings)))
              (progn ,@body)
              (throw 'run-once
                (list :guard-conditions-failed))))))))

;;;; *** Implementation

;;;; We could just make FOR-ALL a monster macro, but having FOR-ALL be
;;;; a preproccessor for the perform-random-testing function is
;;;; actually much easier.

(defun perform-random-testing (generators body)
  (loop
     with random-state = *random-state*
     with total-counter = *max-trials*
     with counter = *num-trials*
     with run-at-least-once = nil
     until (or (zerop total-counter)
               (zerop counter))
     do (let ((result (perform-random-testing/run-once generators body)))
          (ecase (first result)
            (:pass
             (decf counter)
             (decf total-counter)
             (setf run-at-least-once t))
            (:no-tests
             (add-result 'for-all-test-no-tests
                         :reason "No tests"
                         :random-state random-state)
             (return-from perform-random-testing nil))
            (:guard-conditions-failed
             (decf total-counter))
            (:fail
             (add-result 'for-all-test-failed
                         :reason "Found failing test data"
                         :random-state random-state
                         :failure-values (second result)
                         :result-list (third result))
             (return-from perform-random-testing nil))))
     finally (if run-at-least-once
                 (add-result 'for-all-test-passed)
                 (add-result 'for-all-test-never-run
                             :reason "Guard conditions never passed"))))

(defun perform-random-testing/run-once (generators body)
  (catch 'run-once
    (bind-run-state ((result-list '()))
      (let ((values (mapcar #'funcall generators)))
        (funcall body values)
        (cond
          ((null result-list)
           (throw 'run-once (list :no-tests)))
          ((every #'test-passed-p result-list)
           (throw 'run-once (list :pass)))
          ((notevery #'test-passed-p result-list)
           (throw 'run-once (list :fail values result-list))))))))

(defclass for-all-test-result ()
  ((random-state :initarg :random-state)))

(defclass for-all-test-passed (test-passed for-all-test-result)
  ())

(defclass for-all-test-failed (test-failure for-all-test-result)
  ((failure-values :initarg :failure-values)
   (result-list :initarg :result-list)))

(defgeneric for-all-test-failed-p (object)
  (:method ((object for-all-test-failed)) t)
  (:method ((object t)) nil))

(defmethod reason ((result for-all-test-failed))
  (format nil "Falsifiable with ~S" (slot-value result 'failure-values)))

(defclass for-all-test-no-tests (test-failure for-all-test-result)
  ())

(defclass for-all-test-never-run (test-failure for-all-test-result)
  ())

;;;; *** Generators

;;;; Since this is random testing we need some way of creating random
;;;; data to feed to our code. Generators are regular functions which
;;;; create this random data.

;;;; We provide a set of built-in generators.

(defun gen-integer (&key (max (1+ most-positive-fixnum))
                         (min (1- most-negative-fixnum)))
  "Returns a generator which produces random integers greater
than or equal to MIN and less than or equal to MIN."
  (lambda ()
    (+ min (random (1+ (- max min))))))

(defun type-most-negative (floating-point-type)
  (ecase floating-point-type
    (short-float most-negative-short-float)
    (single-float most-negative-single-float)
    (double-float most-negative-double-float)
    (long-float most-negative-long-float)))

(defun type-most-positive (floating-point-type)
  (ecase floating-point-type
    (short-float most-positive-short-float)
    (single-float most-positive-single-float)
    (double-float most-positive-double-float)
    (long-float most-positive-long-float)) )

(defun gen-float (&key bound (type 'short-float) min max)
  "Returns a generator which producs floats of type TYPE. 

BOUND::

Constrains the results to be in the range (-BOUND, BOUND). Default
value is the most-positive value of TYPE.

MIN and MAX::

If supplied, cause the returned float to be within the floating point
interval (MIN, MAX). It is the caller's responsibility to ensure that
the range between MIN and MAX is less than the requested type's
maximum interval. MIN defaults to 0.0 (when only MAX is supplied), MAX
defaults to MOST-POSITIVE-<TYPE> (when only MIN is supplied). This
peculiar calling convention is designed for the common case of
generating positive values below a known limit.

TYPE::

The type of the returned float. Defaults to `SHORT-FLOAT`. Effects the
default values of BOUND, MIN and MAX.

[NOTE]
Since GEN-FLOAT is built on CL:RANDOM the distribution of returned
values will be continuous, not discrete. In other words: the values
will be evenly distributed across the specified numeric range, the
distribution of possible floating point values, when seen as a
sequence of bits, will not be even."
  (lambda ()
    (flet ((rand (limit) (random (coerce limit type))))
      (when (and bound (or min max))
        (error "GET-FLOAT does not support specifying :BOUND and :MAX/:MIN."))
      (if (or min max)
          (handler-bind ((arithmetic-error (lambda (c)
                                             (error "ERROR ~S occured when attempting to generate a random value between ~S and ~S." c min max))))
            (setf min (or min 0)
                  max (or max (type-most-positive type)))
            (+ min (rand (- max min))))
          (let ((min (if bound bound (- (type-most-negative type))))
                (max (if bound bound (type-most-positive type))))
            (ecase (random 2)
              (0 ;; generate a positive number
               (rand max))
              (1 ;; generate a negative number NB: min is actually
               ;; positive. see the if statement above.
               (- (rand min)))))))))

(defun gen-character (&key (code-limit char-code-limit)
                           (code (gen-integer :min 0 :max (1- code-limit)))
                           (alphanumericp nil))
  "Returns a generator of characters.

CODE::

A generater for random integers.

CODE-LIMIT::

If set only characters whose code-char is below this value will be
returned.

ALPHANUMERICP::

Limits the returned chars to those which pass alphanumericp.
"
  (lambda ()
    (loop
       for count upfrom 0
       for char = (code-char (funcall code))
       until (and char
                  (or (not alphanumericp)
                      (alphanumericp char)))
       when (= 1000 count)
       do (error "After 1000 iterations ~S has still not generated ~:[a valid~;an alphanumeric~] character :(."
                 code alphanumericp)
       finally (return char))))

(defun gen-string (&key (length (gen-integer :min 0 :max 80))
                        (elements (gen-character)))
  "Returns a generator which producs random strings of characters.

LENGTH::

A random integer generator specifying how long to make the generated string.

ELEMENTS::

A random character generator which producs the characters in the
string.
"
  (gen-buffer :length length
              :element-type 'character
              :elements elements))

(defun gen-buffer (&key (length (gen-integer :min 0 :max 50))
                     (element-type '(unsigned-byte 8))
                     (elements (gen-integer :min 0 :max (1- (expt 2 8)))))
  "Generates a random vector, defaults to a random (unsigned-byte 8)
vector with elements between 0 and 255.

LENGTH::

The length of the buffer to create (a random integer generator)

ELEMENT-TYPE::

The type of array to create.

ELEMENTS:: 

The random element generator.
"
  (lambda ()
    (let ((buffer (make-array (funcall length) :element-type element-type)))
      (map-into buffer elements))))

(defun gen-list (&key (length (gen-integer :min 0 :max 10))
                      (elements (gen-integer :min -10 :max 10)))
  "Returns a generator which producs random lists.

LENGTH::

As with GEN-STRING, a random integer generator specifying the length of the list to create.

ELEMENTS::

A random object generator.
"
  (lambda ()
    (loop
       repeat (funcall length)
       collect (funcall elements))))

(defun gen-tree (&key (size 20)
                      (elements (gen-integer :min -10 :max 10)))
  "Returns a generator which producs random trees. SIZE control
the approximate size of the tree, but don't try anything above
 30, you have been warned. ELEMENTS must be a generator which
will produce the elements."
  (labels ((rec (&optional (current-depth 0))
             (let ((key (random (+ 3 (- size current-depth)))))
               (cond ((> key 2)
                      (list (rec (+ current-depth 1))
                            (rec (+ current-depth 1))))
                     (t (funcall elements))))))
    (lambda ()
      (rec))))

(defun gen-one-element (&rest elements)
  "Produces one randomly selected element of ELEMENTS.

ELEMENTS::

A list of objects (note: objects, not generators) to choose from."
  (lambda ()
    (nth (random (length elements)) elements)))

;;;; The trivial always-produce-the-same-thing generator is done using
;;;; cl:constantly.
