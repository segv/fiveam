;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-

(in-package :it.bese.fiveam)

(in-suite :it.bese.fiveam)

(def-suite test-suite
    :description "Suite for tests which should fail."
    :in nil)

(defmacro with-test-results ((results test-name) &body body)
  `(let ((,results (with-*test-dribble* nil (run ',test-name))))
     ,@body))

(def-fixture null-fixture ()
  `(progn ,@(&body)))

;;;; Test the checks

(def-test is1 (:suite test-suite)
  (is (plusp 1))
  (is (< 0 1))
  (is (not (plusp -1)))
  (is (not (< 1 0)))
  (is-true t)
  (is-false nil))

(def-test is2 (:suite test-suite :fixture null-fixture)
  (is (plusp 0))
  (is (< 0 -1))
  (is (not (plusp 1)))
  (is (not (< 0 1)))
  (is-true nil)
  (is-false t))

(def-test is (:profile t)
  (with-test-results (results is1)
    (is (= 6 (length results)))
    (is (every #'test-passed-p results)))
  (with-test-results (results is2)
    (is (= 6 (length results)))
    (is (every #'test-failure-p results))))

(def-test signals/finishes ()
  (signals error
    (error "an error"))
  (finishes
   (signals error
    (error "an error"))))

(def-test pass ()
  (pass))

(def-test fail1 (:suite test-suite)
  (fail "This is supposed to fail"))

(def-test fail ()
  (with-test-results (results fail1)
    (is (= 1 (length results)))
    (is (test-failure-p (first results)))))

;;;; non top level checks

(def-test foo-bar ()
  (let ((state 0))
    (is (= 0 state))
    (is (= 1 (incf state)))))

;;;; Test dependencies

(def-test ok (:suite test-suite)
  (pass))

(def-test not-ok (:suite test-suite)
  (fail "This is supposed to fail."))

(def-test and1 (:depends-on (and ok not-ok) :suite test-suite)
  (fail))

(def-test and2 (:depends-on (and ok) :suite test-suite)
  (pass))

(def-test dep-and ()
  (with-test-results (results and1)
    (is (= 3 (length results)))
    ;; we should have one skippedw one failed and one passed
    (is (some #'test-passed-p results))
    (is (some #'test-skipped-p results))
    (is (some #'test-failure-p results)))
  (with-test-results (results and2)
    (is (= 2 (length results)))
    (is (every #'test-passed-p results))))

(def-test or1 (:depends-on (or ok not-ok) :suite test-suite)
  (pass))

(def-test or2 (:depends-on (or not-ok ok) :suite test-suite)
  (pass))

(def-test dep-or ()
  (with-test-results (results or1)
    (is (= 2 (length results)))
    (is (every #'test-passed-p results)))
  (with-test-results (results or2)
    (is (= 3 (length results)))
    (is (= 2 (length (remove-if-not #'test-passed-p results))))))

(def-test not1 (:depends-on (not not-ok) :suite test-suite)
  (pass))

(def-test not2 (:depends-on (not ok) :suite test-suite)
  (fail))

(def-test not ()
  (with-test-results (results not1)
    (is (= 2 (length results)))
    (is (some #'test-passed-p results))
    (is (some #'test-failure-p results)))
  (with-test-results (results not2)
    (is (= 2 (length results)))
    (is (some #'test-passed-p results))
    (is (some #'test-skipped-p results))))

(def-test nested-logic (:depends-on (and ok (not not-ok) (not not-ok))
                    :suite test-suite)
  (pass))

(def-test dep-nested ()
  (with-test-results (results nested-logic)
    (is (= 3 (length results)))
    (is (= 2 (length (remove-if-not #'test-passed-p results))))
    (is (= 1 (length (remove-if-not #'test-failure-p results))))))

(def-test circular-0 (:depends-on (and circular-1 circular-2 or1) 
                      :suite test-suite)
  (fail "we depend on a circular dependency, we should not be tested."))

(def-test circular-1 (:depends-on (and circular-2)
                      :suite test-suite)
  (fail "we have a circular depednency, we should not be tested."))

(def-test circular-2 (:depends-on (and circular-1)
                      :suite test-suite)
  (fail "we have a circular depednency, we should not be tested."))

(def-test circular ()
  (signals circular-dependency
    (run 'circular-0))
  (signals circular-dependency
    (run 'circular-1))
  (signals circular-dependency
    (run 'circular-2)))


(def-suite before-test-suite :description "Suite for before test" :in nil)

(def-test before-0 (:suite before-test-suite)
  (pass))

(def-test before-1 (:depends-on (:before before-0)
                    :suite before-test-suite)
  (fail))

(def-suite before-test-suite-2 :description "Suite for before test" :in nil)

(def-test before-2 (:depends-on (:before before-3)
                    :suite before-test-suite-2)
  (pass))

(def-test before-3 (:suite before-test-suite-2)
  (pass))

(def-test before ()
  (with-test-results (results before-test-suite)
    (is (some #'test-skipped-p results)))
  
  (with-test-results (results before-test-suite-2)
    (is (every #'test-passed-p results))))


;;;; dependencies with symbol
(def-test dep-with-symbol-first (:suite test-suite)
  (pass))

(def-test dep-with-symbol-dependencies-not-met (:depends-on (not dep-with-symbol-first)
                                            :suite test-suite)
  (fail "Error in the test of the test, this should not ever happen"))

(def-test dep-with-symbol-depends-on-ok (:depends-on dep-with-symbol-first :suite test-suite)
  (pass))

(def-test dep-with-symbol-depends-on-failed-dependency (:depends-on dep-with-symbol-dependencies-not-met
                                                    :suite test-suite)
  (fail "No, I should not be tested becuase I depend on a test that in its turn has a failed dependecy."))

(def-test dependencies-with-symbol ()
  (with-test-results (results dep-with-symbol-first)
    (is (some #'test-passed-p results)))

  (with-test-results (results dep-with-symbol-depends-on-ok)
    (is (some #'test-passed-p results)))

  (with-test-results (results dep-with-symbol-dependencies-not-met)
    (is (some #'test-skipped-p results)))

  ;; No failure here, because it means the test was run.
  (with-test-results (results dep-with-symbol-depends-on-failed-dependency)
    (is (not (some #'test-failure-p results)))))


;;;; test for-all

(def-test gen-integer ()
  (for-all ((a (gen-integer)))
    (is (integerp a))))

(def-test for-all-guarded ()
  (for-all ((less (gen-integer))
            (more (gen-integer) (< less more)))
    (is (< less more))))

(def-test gen-float ()
  (macrolet ((test-gen-float (type)
               `(for-all ((unbounded (gen-float :type ',type))
                          (bounded   (gen-float :type ',type :bound 42)))
                  (is (typep unbounded ',type))
                  (is (typep bounded ',type))
                  (is (<= (abs bounded) 42)))))
    (test-gen-float single-float)
    (test-gen-float short-float)
    (test-gen-float double-float)
    (test-gen-float long-float)

    (for-all ((value (gen-float :type 'single-float :min 1 :max 2)))
      (is (typep value 'single-float))
      (is (<= (coerce 1 'single-float) value (coerce 2 'single-float))))))

(def-test gen-character ()
  (for-all ((c (gen-character)))
    (is (characterp c)))
  (for-all ((c (gen-character :code (gen-integer :min 32 :max 40))))
    (is (characterp c))
    (member c (list #\Space #\! #\" #\# #\$ #\% #\& #\' #\())))

(def-test gen-string ()
  (for-all ((s (gen-string)))
    (is (stringp s)))
  (for-all ((s (gen-string :length (gen-integer :min 0 :max 2))))
    (is (<= (length s) 2)))
  (for-all ((s (gen-string :elements (gen-character :code (gen-integer :min 0 :max 0))
                           :length (constantly 2))))
    (is (= 2 (length s)))
    (is (every (curry #'char= #\Null) s))))

(defun dummy-mv-generator ()
  (lambda ()
    (list 1 1)))

(def-test for-all-destructuring-bind ()
  (for-all (((a b) (dummy-mv-generator)))
    (is (= 1 a))
    (is (= 1 b))))

(def-test introspection ()
  (is (= (length (list-all-suites))
         (hash-table-count *suites*))))

(defvar *special-variable* nil)

(def-fixture fixture-for-suite (value)
  (progn
    (setf *special-variable* value)
    (&body)))

(def-suite suite-with-fixture :fixture (fixture-for-suite 42) :in :it.bese.fiveam)

(def-test test-with-suite-fixture (:suite suite-with-fixture)
  (is (= 42 *special-variable*)))

(def-test add-remove-test-from-suite ()
  (let ((*test* (make-hash-table :test 'eql))
        (*suites* (make-hash-table :test 'eql)))
    (def-suite empty :in nil)
    (in-suite empty)
    (is (null (get-test 'foo)))

    (def-test foo (:suite nil) t)
    (is-true (get-test 'foo))
    (is-false (gethash 'foo (tests *suite*)))

    (def-test foo () t)
    (is-true (gethash 'foo (tests *suite*)))

    (def-test foo (:suite nil) t)
    (is-false (gethash 'foo (tests *suite*)))))
