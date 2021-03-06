;;
;; extrategies.lisp
;; Release: Extrategies-6.0.10 (xx/xx/xx)
;;
;; Contact: Cesar Munoz (cesar.a.munoz@nasa.gov)
;; NASA Langley Research Center
;; http://shemesh.larc.nasa.gov/people/cam/Extrategies
;;
;; Copyright (c) 2011-2012 United States Government as represented by
;; the National Aeronautics and Space Administration.  No copyright
;; is claimed in the United States under Title 17, U.S.Code. All Other
;; Rights Reserved.
;;
;; List of strategies in Extrategies:
(defparameter *extrategies* "
%  Printing and commenting: printf, commentf
%  Defining tactics, i.e., local strategies: deftactic
%  Labeling and naming: unlabel*, delabel, relabel, name-label,
%    name-label*, name-replace*, discriminate
%  Copying formulas: copy*, protect
%  Programming: mapstep, mapstep@, with-fresh-labels, with-fresh-labels@,
%    with-fresh-names, with-fresh-names@
%  Control flow: finalize, touch, for, for@, when, when@, unless,
%    unless@, when-label, unless-label, if-label, skip-steps, sklisp
%  Skolem, let-in, inst: skeep, skeep*, skoletin, skoletin*,
%    redlet, redlet*, skodef, skodef*, insteep, insteep*
%  TCCs: tccs-expression, tccs-formula, tccs-formula*, tccs-step, with-tccs
%  Miscellaneous: splash, replaces, rewrites, rewrite*, suffices")

(defparameter *extrategies-version* "Extrategies-6.0.10 (xx/xx/xx)")
(defstruct (TrustedOracle (:conc-name get-))
  (name nil :read-only t)      ; Oracle name 
  (internal nil :read-only t)  ; Internal oracle
  (info nil :read-only t)      ; Information
  stack)                       ; Current stack of trusted proof steps
  
(defparameter *extra-trusted-oracles* nil) ; Hashtable of trusted oracles
(setq *extra-trusted-oracles* (make-hash-table))
(defparameter *extra-disabled-oracles* nil) ; Hashtable of disabled oracles
(setq *extra-disabled-oracles* (make-hash-table))

(defun is-trusted-oracle (orcl)
  (gethash orcl *extra-trusted-oracles*))

(defun is-disabled-oracle (orcl)
  (gethash orcl *extra-disabled-oracles*))

(defun extra-trust-oracle (orcl info &optional internal?) ; Set a trusted oracle
  (let ((torcl (make-TrustedOracle :name orcl :internal internal? :info info)))
    (when (not (is-trusted-oracle orcl))
      (setf (gethash orcl *extra-trusted-oracles*) torcl))))

(extra-trust-oracle '*PVSTypechecker* "PVS Typechecker" t)
(extra-trust-oracle '*PVSGroundEvaluator* "PVS Ground Evaluator" t)

(defun extra-disable-oracle (orcl)
  (let ((torcl (gethash orcl *extra-trusted-oracles*)))
    (when torcl
      (remhash orcl *extra-trusted-oracles*)
      (setf (gethash orcl *extra-disabled-oracles*) torcl))))

(defun extra-enable-oracle (orcl)
  (let ((torcl (gethash orcl *extra-disabled-oracles*)))
    (when torcl
      (remhash orcl *extra-disabled-oracles*)
      (setf (gethash orcl *extra-trusted-oracles*) torcl))))

(defun extra-disable-but (orcls &optional but) 
  (let ((disables (if (member "_" orcls :test #'string=)
		      (extra-list-oracle-names)
		    orcls)))
    (loop for name in (remove-if #'(lambda (n) (member n but :test #'string=))
				 disables)
	  do (extra-disable-oracle (intern name :pvs)))))

(defun extra-list-oracles (&optional (enabled t))
  (sort 
   (loop for orcl being the hash-values of 
	 (if enabled *extra-trusted-oracles* *extra-disabled-oracles*)
	 unless (get-internal orcl)
	 collect (cons (get-name orcl) (get-info orcl)))
   #'(lambda (a b) (string< (car a) (car b)))))

(defun extra-list-oracle-names (&optional (enabled t))
  (mapcar #'car (extra-list-oracles enabled)))

;; Executes command in the operating system and returns a pair (status . string)

(defun extra-system-call (command) 
  (let ((status nil)
	(tmp-file (pvs-tmp-file)))
    (with-open-file (out tmp-file
			 :direction :output :if-exists :supersede)
		    (setq status
			  #+allegro
			  (excl:run-shell-command command
						  :input "//dev//null"
						  :output out
						  :error-output :output)
			  #+sbcl
			  (sb-ext:run-program command
					      nil
					      :input "//dev//null"
					      :output out
					      :error out)
			  #+cmu
			  (extensions:run-program command
						  nil
						  :input "//dev//null"
						  :output out
						  :error out))
		    (cons status (string-trim '(#\Space #\Newline) (file-contents tmp-file))))))

;; Get the absolute path to the PVS NASA library
(defun extra-pvs-nasalib ()
  (car (member "nasalib" *pvs-library-path* :test #'search)))

;;;;;;;;;; Utility functions and additional strategies

;; return a PVS array that represents list
(defun extra-lambda-list (list default &optional test)
  (let ((myl (loop for i from 0 below (length list)
		   for l in list
		   when (or (null test) (funcall test l))
		   append (list i l))))
    (format nil "LAMBDA(i:nat): ~a"
	    (if myl 
		(format nil "~{IF i=~a THEN ~a ELS~}E ~a ENDIF" myl default)
	      default))))

(defstep skip-steps (&rest steps)
  (skip)
  "[Extrategies] Skips steps. This strategy is using for debugging purposes."
  "Skipping steps")

(defstrat sklisp (lispexpr)
  (let ((xxx  (eval lispexpr)))
    (skip))
  "[Extrategies] Evaluates lispexpr and skips")

;; Merge lists
(defun merge-lists-rec (l)
  (when (and l (notany #'null l))
    (let ((cars (mapcar #'car l)))
      (append cars (merge-lists-rec (mapcar #'cdr l))))))

;; (merge-lists '(a1 ... an) '(b1 .. bm)) = (a1 b1 a2 b2 ... ak bk), where k = max(n,m)
(defun merge-lists (&rest l)
  (merge-lists-rec l))

;; Get lisp list of expressions from a PVS list literal
(defun get-list-from-literal (expr)
  (when (list-expr? expr)
    (cons (args1 expr) (get-list-from-literal (args2 expr)))))

;; Get expression from tuple or record, where fons is a list of either field ids or
;; numbers
(defun get-expr-from-obj (expr &rest fons)
  (get-expr-from-obj-rec expr fons))

(defun get-expr-from-obj-rec (expr fons)
  (when expr
    (if fons
	(cond ((and (numberp (car fons)) (tuple-expr? expr))
	       (get-expr-from-obj-rec (nth (car fons) (exprs expr)) (cdr fons)))
	      ((and (or (symbolp (car fons)) (stringp (car fons)))
		    (record-expr? expr))
	       (let ((prexpr (member (car fons) (assignments expr)
				     :test #'(lambda (f a)
					       (string= (id (caar (arguments a))) f)))))
		 (when prexpr
		   (get-expr-from-obj-rec (expression (car prexpr)) (cdr fons))))))
      expr)))

;; Get variables from expression expr except those in but
(defun get-vars-from-expr (expr &optional but)
  (when expr
    (remove-duplicates (get-vars-from-expr-rec expr but) :test #'string=)))

(defun get-vars-from-expr-rec (expr but)
  (cond ((and (is-variable-expr expr)
	      (not (member (expr2str expr) but :test #'string=)))
	 (list (expr2str expr)))
	((let-expr? expr)
	 (append (get-vars-from-expr-rec (argument expr) but)
		 (get-vars-from-expr-rec (expression (operator expr))
					 (append but (mapcar #'id (bindings (operator expr)))))))
	((if-expr? expr)
	 (append (get-vars-from-expr-rec (nth 0 (arguments expr)) but)
		 (get-vars-from-expr-rec (nth 1 (arguments expr)) but)
		 (get-vars-from-expr-rec (nth 2 (arguments expr)) but)))
	((is-function-expr expr)
	 (get-vars-from-expr-rec (argument expr) but))
	((quant-expr? expr) 
	 (get-vars-from-expr-rec (expression expr) (append but (mapcar #'id (bindings expr)))))
	((arg-tuple-expr? expr)
	 (loop for e in (exprs expr)
	       append (get-vars-from-expr-rec e but)))))

;; The parameter numbr is a lisp number (ratio), over is a boolean,
;; and n is the number of decimals in the output. The output is a string representing
;; a decimal number that is exact to the original one up to the n-1 decimal.
;; Furthermore, if over is t, then the output is an over-approximation. Otherwise, the
;; output is an under-approximation.
(defun ratio2decimal (numbr over n)
  (cond ((integerp numbr)
	 (format nil "~d" numbr))
	((numberp numbr)
	 (let* ((r (abs (* numbr (expt 10 n))))
		(i (truncate r)))
	   (if (= i r)
	       (format nil "~:[-~;~]~a" (>= numbr 0) (exact-fp (abs numbr)))
	     (let* ((f (format nil "~~~a,'0d" (1+ n)))
		    (s (format nil f (+ i (if (iff over (< numbr 0)) 0 1))))
		    (d (- (length s) n)))
	       (format nil "~:[-~;~]~a~:[.~;~]~a"
		       (>= numbr 0)
		       (subseq s 0 d)
		       (= n 0)
		       (subseq s d))))))))

(defun is-var-decl-expr (expr)
  (and (name-expr? expr)
       (let ((decl (declaration (resolution expr))))
	 (or (var-decl? decl)
	     (bind-decl? decl) (skolem-const-decl? decl) (formal-const-decl? decl)
	     (and (const-decl? decl) (null (def-axiom decl)))))))

;; Constants that are uninterpreted are considered to be variables
(defun is-variable-expr (expr &optional vars)
  (and expr
       (or (is-var-decl-expr expr)
	   (and (or (fieldappl? expr) (projappl? expr))
		(is-var-decl-expr (argument expr))))
       (or (null vars)
	   (member (expr2str expr) (enlist-it vars) :test #'string=))))

(defun is-variable-expr? (expr vars)
  (and vars (is-variable-expr expr vars)))

;; Constants that are uninterpreted are considered to be variables unless they appear 
;; in but
(defun is-const-decl-expr (expr &optional but) 
  (and (name-expr? expr)
       (let ((decl (declaration (resolution expr))))
	 (or (and (const-decl? decl)
		  (not (skolem-const-decl? decl))
		  (or (consp (def-axiom decl))
		      (member (id expr) (enlist-it but) :test #'string=)))
	     (and (formal-const-decl? decl)
		  (member (id expr) (enlist-it but) :test #'string=))))))

;; Is constant expr in names (null names means any name)? Constants that are uninterpreted 
;; are not considered to be constants
(defun is-constant-expr (expr &optional names)
  (and expr
       (or (is-const-decl-expr expr)
	   (and (or (fieldappl? expr) (projappl? expr))
		(is-const-decl-expr (argument expr))))
       (or (null names)
	   (member (expr2str expr) (enlist-it names) :test #'string=))))

(defun is-constant-expr? (expr names)
  (and names (is-constant-expr expr names)))

;; Returns true if expr is a function application of function name
(defun is-function-expr (expr &optional names)
  (and expr
       (application? expr)
       (name-expr? (operator expr))
       (or (null names)
	   (member (id (operator expr)) (enlist-it names) :test #'string=))))

(defun is-function-expr? (expr funs)
  (and funs (is-function-expr expr funs)))

;; Expression with an infix operator?
(defun is-infix-operator (term-obj op)
  (and (infix-application? term-obj)
       (name-expr? (operator term-obj))
       (eq (id (operator term-obj)) op)))

;; Expression with a prefix operator?
(defun is-prefix-operator (term-obj op)
  (and (unary-application? term-obj)
       (name-expr? (operator term-obj))
       (eq (id (operator term-obj)) op)))

;; If l is not a list put it into a list
(defun enlist-it (l)
  (if (and (listp l) (not (equal (car l) '!)))
      l
    (list l)))

;; Pairs lists ls1 and ls2. Unless cut? is t, lists are completed with the last
;; elements if they have different length. If list? is t, pairs with list instead of cons
(defun pair-lists (ls1 ls2 &optional cut? list? prevl1 prevl2)
  (when (if cut? (and ls1 ls2) (or ls1 ls2))
    (let ((l1 (or (car ls1) prevl1))
	  (l2 (or (car ls2) prevl2)))
      (cons (if list? (list l1 l2) (cons l1 l2))
	    (pair-lists (cdr ls1) (cdr ls2) cut? list? l1 l2)))))

;; a <=> b
(defun iff (a b)
  (equal (not a) (not b)))

;; Get all keys of a hash table
(defun get-hash-keys (hash)
  (loop for k being the hash-key of hash
	collect k))

(defparameter *extra-label-counter* 0) ;; Counter for generating new labels

;; Generates a label with given prefix that is fresh in the current context
(defun freshlabel (prefix)
  (when *current-context*
    (let* ((alllabels (union (extra-get-labels '*)
			     (extra-get-labels '* t)))
	   (counter   (incf *extra-label-counter*))
	   (nn        (intern (format nil "~a:~a" prefix counter) :pvs)))
      (if (member nn alllabels)
	  (loop for i from 1
		for nn = (intern (format nil "~a_~a:~a" prefix i counter) :pvs)
		unless (member nn alllabels)
		return nn)
	nn))))

;; Generates a label with given prefix that is fresh in the current context
(defun freshlabels (prefix n)
  (when *current-context*
    (loop for i from 1 to n
	  collect (freshlabel prefix))))

;; Check if name has been defined in the proof context
(defun check-name (name)
  (let ((pc-name (pc-parse name 'expr)))
    (resolve pc-name 'expr nil *current-context*)))

;; Check if an identifier is a free variable (and not in but list)
;; If a type is provided, check if the given name is a free variable of the given type.
(defun is-freevar (name &optional type but)
  (and (not (member name but :test #'string=))
       (let* ((pc-name (pc-parse name 'expr))
	      (rs      (resolve pc-name 'expr nil *current-context*)))
	 (if type
	     (and (name-expr? pc-name)
		  (not (declared? (id pc-name) *current-context*))
		  (every #'(lambda (r) (and (resolution? r)
					    (or (var-decl? (declaration r))
						(not (compatible? (type r)
								  type)))))
			 rs))
	   (null rs)))))

(defparameter *extra-name-counter* 0) ;; Counter for generating new names

;; Generates a name with given prefix that is fresh in the current context (and not in but list)
(defun freshname (prefix)
  (when *current-context*
    (let* ((counter (incf *extra-name-counter*))
	   (nn      (format nil "~a_~a" prefix counter)))
      (if (is-freevar nn) nn
	(loop for i from 1
	      for nn = (format nil "~a_~a_~a" prefix i counter)
	      when (is-freevar nn)
	      return nn)))))
        
;; Generates n names with given prefix that are fresh in the current context
(defun freshnames (prefix n)
  (when *current-context*
    (loop for i from 1 to n
	  collect (freshname prefix))))
  
;; Get a list of formula numbers from fnums
(defun extra-get-fnums (fnums &optional enlist?)
  (if (or (not enlist?) (atom fnums) (member (car fnums) '(^ +^ -^)))
    (map-fnums-arg fnums)
    (mapcar #'map-fnums-arg fnums)))

;; Get a formula number from fnum
(defun extra-get-fnum (fnum)
  (car (extra-get-fnums fnum)))

;; Get a PVS object from expr, where expr can be speficied as a formula or a string
;; or using Manip's location
(defun extra-get-expr (expr &optional (tc t))
  (cond ((expr? expr) expr)
	((or (numberp expr) (symbolp expr))
	 (extra-get-formula expr))
	((stringp expr)
	 (let ((e (pc-parse expr 'expr)))
	   (if tc (pc-typecheck e) e)))
	((and (listp expr) (equal (car expr) '!))
	 (let* ((ecar (car (eval-ext-expr expr)))
		(e    (when ecar (ee-pvs-obj ecar))))
	   (when (expr? e) e)))))

(defun extra-get-expstr (expr &optional (tc t))
  (expr2str (extra-get-expr expr tc)))

;; Returns list of formula numbers not in fnums
(defun extra-get-but-fnums (fnums &key (all '*))
  (when all
    (let ((forms (extra-get-fnums all))
	  (but   (extra-get-fnums fnums)))
      (set-difference forms but))))

;; Get sequent formula from an *actual* formula number in the sequent.
(defun extra-get-seqf-from-fnum (fn)
  (when fn
    (let* ((fs    (if (> fn 0) (p-sforms *goal*) (n-sforms *goal*)))
	   (index (- (abs fn) 1)))
      (nth index fs))))
  
;; Get list of sequent formulas in fnums
;; If hidden? is t fnums should be a list of numbers or one of the symbols *,-,+
(defun extra-get-seqfs (fnums &optional hidden?)
  (when fnums
    (if hidden?
	(select-seq (hidden-s-forms *goal*) fnums)
      (loop for fn in (extra-get-fnums fnums)
	    for seqf = (extra-get-seqf-from-fnum fn)
	    when seqf
	    collect seqf))))

;; Get sequent formula in fnum
(defun extra-get-seqf (fnum &optional hidden?)
  (when fnum
    (car (extra-get-seqfs fnum hidden?))))

;; Get formula from an *actual* formula number in the sequent.
(defun extra-get-formula-from-fnum (fn)
  (when fn 
    (let* ((seqf (extra-get-seqf-from-fnum fn)))
      (when seqf
	(if (> fn 0)
	    (formula seqf)
	  (argument (formula seqf)))))))

;; Get a formula given a FNUM, which can be a label.
(defun extra-get-formula (fnum)
  (when fnum
    (extra-get-formula-from-fnum (extra-get-fnum fnum))))

;; Get list of labels of an *actual* formula number
(defun extra-get-labels-from-fnum (fn)
  (when fn
    (label (extra-get-seqf-from-fnum fn))))

;; Generalized union
(defun union-list (l)
  (when l (union (car l) (union-list (cdr l)))))

;; Get list of labels of formulas in fnums
;; If hidden? is t fnums should be a list of numbers or one of the symbols *,-,+
(defun extra-get-labels (fnums &optional hidden?)
  (when fnums
    (union-list (loop for seq in (extra-get-seqfs fnums hidden?)
		      collect (label seq)))))

;; Returns relation if expr is an order relation 
(defun is-order-relation (expr)
  (let ((rel (car (is-relation expr))))
    (unless (equal rel '=) rel)))

;; Returns symbol that is the logical negation of the order relation rel
(defun not-relation (rel)
  (cond ((equal rel '<)  '>=)
	((equal rel '<=) '>)
	((equal rel '>)  '<=)
	((equal rel '>=) '<)
	((equal rel '=) '/=)
	((equal rel '/=) '=)))

;; Returns symbol that is the arithmetic negation of the order relation rel
(defun neg-relation (rel)
  (cond ((equal rel '<)  '>)
	((equal rel '<=) '>=)
	((equal rel '>) '<)
	((equal rel '>=)  '<=)
	((equal rel '=) '=)
	((equal rel '/=) '/=)))
  
(defun relation2num (rel)
  (when rel
    (cond ((equal rel '<)  -2)
	  ((equal rel '<=) -1)
	  ((equal rel '=)   0)
	  ((equal rel '>=)  1)
	  ((equal rel '>)   2))))

(defun num2relation (num)
  (when num
    (cond ((= num -2) '<)
	  ((= num -1) '<=)
	  ((= num 0) '=)
	  ((= num 1) '>=)
	  ((= num 2) '>))))

(defun extra-and-rel (rel1 rel2)
  (let ((o1 (relation2num rel1))
	(o2 (relation2num rel2)))
    (cond ((equal rel1 rel2) rel1)    ; Same relation
	  ((null rel1) rel2)          ; No relation vs. some relation
	  ((null rel2) rel1)          ; Some relation vs. no relation
	  ((and (null o1) 
		(> (abs o2) 1)) rel2) ; /= vs. {>,<}
	  ((and (null o1)
		(> (abs o2) 0))       ; /= vs. {<=, >=}
	   (num2relation (* (sign o2) (1+ (abs o2)))))
	  ((null o1) nil)             ; /= v.s =
	  ((null o2)                  ; Some relation vs. /=
	   (extra-and-rel rel2 rel1))
	  ((and (= o1 0)              ; = vs. {<=,>=}
		(= (abs o2) 1)) rel1)
	  ((= o1 0) nil)                ; = vs. {<, >}
	  ((= o2 0) 
	   (extra-and-rel rel2 rel1))
	  ((iff (> o1 0) (> o2 0))      ; Same direction
	   (num2relation (* (sign o1) 2))))))

;; Returns a numerical constant where expr is a ground number expression
;; If shallow? then don't ground evaluate the expression
(defun extra-get-number-from-expr (fmexpr &optional shallow?)
  (let ((expr (extra-get-expr fmexpr)))
    (when expr
      (cond ((rational-expr? expr)
	     (number expr))
	    ((decimal? expr)
	     (/ (number (args1 expr)) (number (args2 expr))))
	    ((not shallow?)
	     (let ((val (evalexpr expr)))
	       (when (expr? val)
		 (extra-get-number-from-expr val t))))))))

(defun is-bool-type (type)
  (and (type-name? type)
       (equal (id type) (id *boolean*))))

;; Returns true if type is a number type
(defun is-number-type (type)
  (or (and (type-name? type)
           (equal (id type) (id *number*)))
      (and (subtype? type)
	   (is-number-type (supertype type)))))

;; Merges two lists in one string using 
;; :empty as the empty-string
;; :conc as the string-concatenator
;; :sep as the string-separator
;; For instance (merge2str '("a" "b" "c") '("A" "B" "C") :conc "-" :sep ",")
;; returns "a-A,b-B,c-C"

(defun merge2str (l1 l2 &key (empty "") (conc "") (sep ""))
  (let ((l (loop for a in l1
		 for b in l2
		 collect (format nil "~a~a~a" a conc b))))
    (if l (format nil "~a~{~a~}" (car l) (loop for ab in (cdr l) append (list sep ab)))
      empty)))
  
;; Sign of n (note that 0 returns 1).
(defun sign (n)
  (if (>= n 0) 1 -1))
  
;; String to int.
(defun str2int (str)
  (multiple-value-bind (n l) (parse-integer str :junk-allowed t)
    (when (and n (= (length str) l)) n)))

;; Expression to string (tries to minimize parentheses)
(defun expr2str (expr)
  (when expr
    (cond ((stringp expr) expr)
	  ((numberp expr) (format nil "~a" expr))
	  ((and (infix-application? expr)
		(= (parens expr) 0)
		(not (is-relation expr)))
	   (format nil "(~a)" expr))
	  ((and (or (name-expr? expr)
		    (rational-expr? expr))
		(> (parens expr) 0))
	   (format nil "~a" (copy expr 'parens 0)))
	  (t (format nil "~a" expr)))))
  
;; Creates a list of numbers in the range from..to.
(defun fromto (from to) 
  (cond 
   ((< from to) (cons from (fromto (+ from 1) to)))
   ((> from to) (cons from (fromto (- from 1) to)))
   (t (list to))))

;; Returns the minimum of a list of numbers.
(defun minlist (l)
  (eval (cons 'min l)))

;; Returns the maximum of a list of numbers.
(defun maxlist (l)
  (eval (cons 'max l)))

;; Removes numbers in list fnums that appear before from.
(defun remove-before (from fnums)
  (when fnums
    (if (= from (car fnums))
	fnums
        (remove-before from (cdr fnums)))))
	       
;; Removes numbers in list fnums that appear after to.
(defun remove-after (to fnums)
  (when fnums
    (let ((a (car fnums)))
      (if (= to a)
	  (list a)
          (cons a (remove-after to (cdr fnums)))))))

;; Let l=(l0..ln), if flag then returns (l0,l2,..),
;; otherwise returns (l1,l3,..).
(defun each-other (l flag)
  (when l
    (if flag
	(cons (car l)(each-other (cdr l) (not flag)))
      (each-other (cdr l) (not flag)))))

;; Removes position p of list l.
(defun removepos (p l)
  (when l
    (if (= p 0) (cdr l)
      (cons (car l) (removepos (- p 1) (cdr l))))))

;; Find the first formula that satisfies test. Test is a function with two arguments
;; the first of which is a formula number and the second is the corresponding expression.
;; Returns the first arguments that make the test hold
(defun first-formula (fnums &key test)
  (loop for fn in (extra-get-fnums fnums)
	for form = (extra-get-formula-from-fnum fn)
	when (or (null test) (funcall test fn form))
	return (list fn form)))

;; Extended interval

(defparameter *extra-varranges* nil) ;; List of extended intervals (xterval), one per variable
(defparameter *extra-evalexprs* nil) ;; Association list of PVS ground expressions and evaluations

(defun extra-reset-evalexprs ()
  (setq *extra-evalexprs* nil))

(defun extra-evalexprs ()
  (mapcar #'(lambda (x) (list (car x) (cdr x))) *extra-evalexprs*))

(defun extra-add-evalexpr (fmexpr)
  (let* ((expr (extra-get-expr fmexpr))
	 (val  (assoc expr *extra-evalexprs* :test #'compare*)))
    (or (cdr val)
	(let ((exval (evalexpr expr)))
	  (when (expr? exval) 
	    (unless (compare* expr exval)
	      (push (cons expr exval) *extra-evalexprs*))
	    exval)))))

(defhelper extra-evalexprs (evalexprs &optional lbl) 
  (when evalexprs
    (let ((eqs (expr2str (mk-conjunction (mapcar #'(lambda (x) (mk-equation (car x) (cadr x))) evalexprs)))))
      (with-fresh-labels 
       (!xeqs)
       (branch (case eqs)
	       ((then (label !xeqs -1)
		      (flatten !xeqs)
		      (if lbl
			  (relabel lbl !xeqs)
			(replaces !xeqs :hide? nil))
		      (hide !xeqs))
		(eval-formula))))))
 "[Extrategies] Internal strategy to be used in conjunction with the functions extra-reset-evalexpr, 
extra-add-evalexprm and extra-evalexprs. Parameter evalexprs is a list of expressions and ground 
evaluations. This strategy will introduce, as hypotheses, the equalities for those ground evaluations." "")

(defstruct (xterval)
  (lb nil) ; lower bound (numerical)
  (ub nil) ; upper bound (numerical)
  (lb-closed nil) ; lower bound is closed
  (ub-closed nil)) ; upper bouund is closed

(defun xterval2str (xv)
  (format nil "~:[(~;[~]~a,~a~:[)~;]~]"
	  (and xv (xterval-lb-closed xv))
	  (if (and xv (xterval-lb xv)) (xterval-lb xv) "-oo")
	  (if (and xv (xterval-ub xv)) (xterval-ub xv) "oo")
	  (and xv (xterval-ub-closed xv))))

(defun get-var-range-from-interval (var fmexpr) 
  (let* ((expr (extra-get-expr fmexpr))
	 (val  (extra-add-evalexpr expr)))
    (when (record-expr? val)
      (let* ((lb (extra-get-number-from-expr (get-expr-from-obj val 'lb) t))
	     (ub (extra-get-number-from-expr (get-expr-from-obj val 'ub) t))
	     (bb (get-expr-from-obj val 'bounded_below))
	     (ba (get-expr-from-obj val 'bounded_above))
	     (cb (get-expr-from-obj val 'closed_below))
	     (ca (get-expr-from-obj val 'closed_above)))
	(cond ((and lb ub bb ba cb ca)
	       (if (extra-is-true bb)
		   (extra-insert-range var lb t (extra-is-true cb)))
	       (if (extra-is-true ba)
		   (extra-insert-range var ub nil (extra-is-true ca))))
	      ((and lb ub)
	       (extra-insert-range var lb t t)
	       (extra-insert-range var ub nil t)))))))

(defun get-var-range-from-abs (var fmexpr closed) 
  (let* ((expr (extra-get-expr fmexpr))
	 (val  (extra-add-evalexpr expr)))
    (when val
      (let ((ub (extra-get-number-from-expr val t)))
	(when ub
	  (extra-insert-range var (- ub) t closed)
	  (extra-insert-range var ub nil closed))))))
    
(defun get-var-range-from-rel (varexpr fmexpr rel)
  (let* ((closed (or (equal rel '>=) (equal rel '<=)))
	 (neg    (is-prefix-operator varexpr '-))
	 (nrel   (if neg (not-relation rel) rel))
	 (islb   (or (equal nrel '>=) (equal nrel '>))))
    (if (and (is-function-expr varexpr 'abs)
	     (not islb))
	(get-var-range-from-abs (args1 varexpr) fmexpr closed)
      (let* ((expr (extra-get-expr fmexpr))
	     (val  (extra-add-evalexpr expr)))
	(when val
	  (let ((num (extra-get-number-from-expr val t)))
	    (when num
	      (extra-insert-range (if neg (args1 varexpr) varexpr)
				  (if neg (- num) num)
				  islb closed))))))))
	  
; If neg is t, formula appears in a negated form
(defun get-var-range-from-formula (fm vars &optional neg)
  (if (and (not neg)
	   (is-function-expr fm "##")
	   (is-variable-expr? (args1 fm) vars))
      (get-var-range-from-interval (args1 fm) (args2 fm))
    (let* ((nrel (is-order-relation fm))
	   (rel  (if neg (not-relation nrel) nrel)))
      (when rel 
	(cond ((or (is-variable-expr? (args1 fm) vars)
		   (and (or (is-prefix-operator (args1 fm) '-)
			    (is-function-expr (args1 fm) 'abs))  
			(is-variable-expr? (args1 (args1 fm)) vars)))
	       (get-var-range-from-rel (args1 fm) (args2 fm) rel))
	      ((or (is-variable-expr? (args2 fm) vars)
		   (and (or (is-prefix-operator (args2 fm) '-) 
			    (is-function-expr (args2 fm) 'abs))
			(is-variable-expr? (args1 (args2 fm)) vars)))
	       (get-var-range-from-rel (args2 fm) (args1 fm) (neg-relation rel))))))))

;; Get range information for each variable in vars from relational formulas fms.
;; vars is a list of the form (<V1> ... <V2>), where <Vi> has either the
;; form <vi> or (<vi> "<expr>"). The latter case explicitly specifies the range of the variable <vi>.
;; The expression <expr> should evaluate to either an interval or an extended interval

;; Return the list of variables.
(defun extra-get-var-ranges (fms vars)
  (setq *extra-varranges* (make-hash-table :test #'equal)) 
  (let ((uvars (remove-if #'listp vars)))
    (loop for fm in fms
	  do (if (negation? fm)
		 (get-var-range-from-formula (args1 fm) uvars t)
	       (get-var-range-from-formula fm uvars))))
  (loop for v in vars
	when (listp v)
	do (get-var-range-from-interval (car v) (cadr v)))
  vars)

(defun extra-var-name (iavar) (if (listp iavar) (car iavar) iavar))

;; Put a variable bound in the hash table *extra-varranges*
(defun extra-insert-range (var val islb isclosed)
  (let* ((var (format nil "~a" var))
	 (xv  (or (gethash var *extra-varranges*)
		  (make-xterval)))
	 (did (if islb 
		  (when (or (null (xterval-lb xv))
			    (< (xterval-lb xv) val)
			    (and (= (xterval-lb xv) val) 
				 (xterval-lb-closed xv)
				 (not isclosed)))
		    (setf (xterval-lb xv) val)
		    (setf (xterval-lb-closed xv) isclosed)
		    t)
		(when (or (null (xterval-ub xv))
			  (> (xterval-ub xv) val)
			  (and (= (xterval-ub xv) val)
			       (xterval-ub-closed xv)
			       (not isclosed)))
		  (setf (xterval-ub xv) val)
		  (setf (xterval-ub-closed xv) isclosed)
		  t))))
    (when did
      (setf (gethash var *extra-varranges*) xv))))

; If neg is t, formula appears in a negated form
(defun get-var-var-relation-from-formula (fm var1 var2 &optional neg)
  (let* ((nrel (or (car (is-relation fm)) (car (is-function-expr fm '/=))))
	 (rel  (if neg (not-relation nrel) nrel))
	 (vs1  (list var1))
	 (vs2  (list var2)))
    (when rel
      (cond ((and (is-variable-expr? (args1 fm) vs1)
		  (is-variable-expr? (args2 fm) vs2))
	     rel)
	    ((and (is-variable-expr? (args1 fm) vs2)
		  (is-variable-expr? (args2 fm) vs1))
	     (neg-relation rel))
	    ((and (is-prefix-operator (args1 fm) '-)
		  (is-prefix-operator (args2 fm) '-))
	     (cond ((and (is-variable-expr? (args1 (args1 fm)) vs1)
			 (is-variable-expr? (args1 (args2 fm)) vs2))
		    (neg-relation rel))
		   ((and (is-variable-expr? (args1 (args1 fm)) vs2)
			 (is-variable-expr? (args1 (args2 fm)) vs1))
		    rel)))))))

;; Get relation between two variables var1 and var2 in list of formulas fms
(defun extra-get-var-var-relation (fms var1 var2 &optional rel)
  (if fms
      (let* ((fm   (car fms))
	     (nrel (get-var-var-relation-from-formula
		    (if (negation? fm) (args1 fm) fm) var1 var2 (negation? fm))))
	(extra-get-var-var-relation (cdr fms) var1 var2 (extra-and-rel rel nrel)))
    rel))

(defun extra-is-true (expr)
  (and (name-expr? expr) (same-declaration expr *true*)))

(defun extra-is-false (expr)
  (and (name-expr? expr) (same-declaration expr *false*)))

;;;;;;;;;; Extrategies

;;; Printing and commenting

(defstrat printf (msg &rest args)
  (let ((msg (format nil "~%~a" msg))
	(xxx (apply 'format (cons t (cons msg args)))))
    (skip))
  "[Extrategies] Prints the Lisp formatted string MSG using the format arguments
ARGS. ARGS must be constant values.")

(defstrat commentf (msg &rest args)
  (let ((msg (apply 'format (cons nil (cons msg args)))))
    (comment msg))
  "[Extrategies] Adds the formatted comment MSG to the sequent using the format
arguments ARGS. ARGS can only have constant values.")

;;; Labeling and naming

(defstep unlabel* (&optional (fnums *) label hidden?)
  (let ((fs  (extra-get-fnums fnums)))
    (if label
	(let ((lbl     (flatten-labels label))
	      (qhidden (list 'quote hidden?))
	      (qfs     (list 'quote fs)))
	  (mapstep #'(lambda(x)`(unlabel ,qfs ,x :hidden? ,qhidden)) lbl))
      (unlabel fs :hidden? hidden?)))
  "[Extrategies] Removes specified LABEL(s) (or all labels if LABEL is nil) from FNUMS.
FNUMS are considered to be hidden formulas when hidden? is set to t."
  "Removing ~1@*~:[all labels~;label(s) ~:*~a~] from ~@*~a")

(defstep delabel (labl &optional hide? (hidden? t))
  (let ((fnums (extra-get-fnums labl))
	(seqfs  (when hidden? (extra-get-seqfs labl t))))
    (then (when fnums
	    (unlabel* fnums labl)
	    (when hide? (hide fnums)))
	  (when seqfs
	    (let ((lbs (flatten-labels labl)))
	      (mapstep #'(lambda(x)`(unlabel :label ,x :hidden? t)) lbs)))))
  "[Extrategies] Removes LABL(s). If HIDE? is t, hides the delabeled formulas.
If HIDDEN? is t, LABL(s) are also removed from hidden formulas."
  "Removing label(s) ~a")

(defun set-pairing (l)
  (if (is-pairing l) l
    (let ((el (enlist-it l)))
      (when el
	(cons ':pairing el)))))

(defun is-pairing (l)
  (and (listp l)
       (equal (car l) ':pairing)))

(defun flatten-labels (label)
  (when label
    (if (atom label) (list label)
      (append (flatten-labels (car label))
	      (flatten-labels (cdr label))))))

(defhelper relabel__ (labl fnums)
  (when labl
    (let ((labs   (flatten-labels labl))
	  (qfnums (list 'quote fnums)))
      (mapstep #'(lambda(x)`(label ,x ,qfnums :push? t)) labs)))
  "[Extrategies] Internal strategy." "")

(defstep relabel (labl fnums &optional pairing? (push? t))
  (when labl
    (let ((pair (or pairing? (is-pairing labl)))
	  (lbs  (cond (pairing? labl)
		      (pair     (cdr labl))
		      (t        (flatten-labels labl))))
	  (lfs  (extra-get-fnums fnums pair))
	  (lbfs (if pair (pair-lists lbs lfs t)
		  (mapcar #'(lambda (x) (cons x lfs)) lbs))))
      (then
       (unless push? (unlabel* fnums))
       (mapstep #'(lambda(x)`(relabel__ ,(car x) ,(cdr x) :push? t)) lbfs))))
  "[Extrategies] Labels FNUMS as LABL(s), keeping the old ones. If PAIRING? is t and
LABL is a list of the form (LAB1 ... LABn), each LABi is paired to the i-th formula in FNUM.
If PUSH? is t, then the new labels are added to the existing ones. Otherwise, the new labels
replace all existing ones.

ADVANCED USE: If LABL has the form (:pairing LAB1 ... LABn), PAIRING? is set to t."
  "Labeling formula(s) ~1@*~a as ~@*~a")

(defstep name-label (name expr &optional label (fnums *) (dir lr) hide?
			  (tcc-step (extra-tcc-step)) tcc-label)
  (let ((labl    (unless (equal label 'none) (or label (format nil "~a:" name))))
	(estr    (extra-get-expstr expr))
	(tccsome (and (not (equal tcc-label 'none)) tcc-label))
	(tccnone (or (equal tcc-label 'none)
		     (and (null tcc-label) (equal label 'none))))
	(labtcc  (or tccsome
		     (if tccnone (freshlabel "nlt")
		       (if label (mapcar #'(lambda (lb)
					     (format nil "~a-TCC:" lb))
					 (flatten-labels label))
			 (format nil "~a-TCC:" name))))))
    (when estr
      (if (not (check-name name))
	  (then
	   (with-fresh-labels@
	    ((!nml fnums)
	     (!nlx))
	    (tccs-expression estr :label labtcc :tcc-step tcc-step)
	    (branch (discriminate (name name estr) (labl !nlx))
		    ((then (when fnums (replace !nlx !nml))
			   (let ((flagdir (equal dir 'rl)))
			     (when@ flagdir (swap-rel !nlx)))
			   (when hide? (hide !nlx)))
		     (then
		      (when tcc-step
			(hide-all-but (labtcc !nlx))
			(flatten)
			(assert))
		      (delabel labl)))))
	   (unless tccsome
	     (if tccnone
		 (delabel labtcc :hide? t)
	       (hide labtcc))))
	(printf "Name ~a already exists" name))))
  "[Extrategies] Adds formula EXPR=NAME, where NAME is a new name, as
a hypothesis and replaces EXPR by NAME in FNUMS. The added formula is
labeled LABEL:, by default LABEL is set to NAME. DIR indicates the
direction of the name definition, e.g., EXPR=NAME, if DIR is lr, or
NAME=EXPR, if DIR is rl. The added formula is hidden when HIDE? is
t. If TCC-STEP is not null and EXPR yields TCCs, these TCCs are added
as hypotheses to the main branch. If a TCC-LABEL is provided, these
hypotheses are labeled TCC-LABEL. Otherwise, these hypotheses are
labeled LABEL-TCC: and hidden from the sequent.  In branches other
than the main branch, the strategy tries to discharge these TCCs with
the proof command TCC-STEP."
"Naming ~1@*~a as ~@*~a")

(defun split-names-exprs (nmex label plabel tcclabel ptcclabel tccstp ptccstp)
  (when (> (length nmex) 1)
    (let ((nept (list (car nmex) (cadr nmex)
		      (if plabel (car label) label)
		      (if ptccstp (car tccstp) tccstp)
		      (if ptcclabel (car tcclabel) tcclabel))))
      (cons nept (split-names-exprs (cddr nmex)
				    (if plabel (cdr label) label)
				    plabel
				    (if ptcclabel (cdr tcclabel) tcclabel)
				    ptcclabel
				    (if ptccstp (cdr tccstp) tccstp)
				    ptccstp)))))

(defstep name-label* (names-and-exprs &optional label (fnums *) (dir lr) hide?
				      (tcc-step (extra-tcc-step)) tcc-label)
  (let ((plabs    (is-pairing label))
	(labs     (cond (plabs (cdr label))
			((atom label) label)
			(t (flatten-labels label))))
	(ptcclabs (is-pairing tcc-label))
	(tcclabs  (cond (ptcclabs (cdr tcc-label))
			((atom tcc-label) tcc-label)
			(t (flatten-labels tcc-label))))
	(ptccstp  (is-pairing tcc-step))
	(tccstp   (if ptccstp (cdr tcc-step) tcc-step))
	(nmex     (split-names-exprs names-and-exprs labs plabs tcclabs ptcclabs tccstp ptccstp))
	(qdir     (list 'quote dir))
	(qhide    (list 'quote hide?)))
    (with-fresh-labels
     (!nls fnums)
     (let ((qnls (list 'quote !nls)))
       (mapstep@ #'(lambda(x)`(name-label ,(nth 0 x) ,(nth 1 x) :label ,(nth 2 x) :fnums ,qnls
					  :dir ,qdir :hide? ,qhide
					  :tcc-step ,(nth 3 x) :tcc-label ,(nth 4 x)))
		 nmex))))
  "[Extrategies] Iterates name-label on NAMES-AND-EXPRS, which is assumed to be a list of the form
(NAME1 EXPR1 NAME2 EXPR2 ... NAMEn EXPRn). Options are provided as in name-label.

ADVANCED USE: The options LABEL, TCC-STEP, and TCC-LABEL can be lists of the form (:pairing e1 ... en).
In this case, each ei is paired to the i-th element in NAMES-AND-EXPRS."
  "Interating name-label on a list of names and expressions")

(defstep name-replace* (names-and-exprs &optional (fnums *) (dir lr) hide?
					(tcc-step (extra-tcc-step)) tcc-label)
  (name-label* names-and-exprs :label none :fnums fnums :dir dir :hide? hide?
	       :tcc-step tcc-step :tcc-label tcc-label)
  "[Extrategies] Same as name-label* without labeling the formulas."
  "Iterating name-replace")

(defstep discriminate (step &optional label strict?)
    (if label
	(with-fresh-labels
	 (!dsc)
	 (if strict?
	     (then (with-labels step !dsc)
		   (relabel label !dsc))
	   (then (relabel !dsc *)
		 step
		 (relabel label (^ !dsc)))))
      step)
  "[Extrategies] Labels formulas generated by STEP as LABEL(s). When STRICT? is set to t,
all formulas that are considered new by PVS are also labeled."
  "Labeling new formulas~*~@[ as ~a~]")

;;; Strategy programming

(defstrat mapstep (funstep &optional list list?)
  (when list
    (let ((step (funcall (eval funstep) (if list? list (car list))))
	  (rest (cdr list)))
      (then step
	    (mapstep funstep rest list?))))
  "[Extrategies] Sequentially applies FUNSTEP to each element of LIST. FUNSTEP is a function
in Lisp that takes one argument and returns a proof command. After each application of FUNSTEP,
the resulting proof command is applied to all branches. When LIST? is nil, the argument of
FUNSTEP represents the head of the list at each iteration. For example,

(mapstep #'(lambda(x)`(name ,x \"1\")) (\"One\" \"Uno\"))

behaves as (then (name \"One\" \"1\") (name \"Uno\" \"1\")).

If LIST? is t, the argument of FUNSTEP represents the complete list at each iteration.
For example,

(mapstep #'(lambda(x)`(name ,(car x) ,(length x))) (\"Two\" \"One\") :list? t)

behaves as (then (name \"Two\" 2) (name \"One\" 1)).

Technicality: Note the use of quotation and anti-quotation in the examples. Variables in FUNSTEP
other than FUNSTEP's parameter can be unquoted only if they were defined outside FUNSTEP
as (list 'quote <something>), e.g.,

(let ((lbs (list 'quote '(\"a\" \"b\" \"c\"))))
  (mapstep #'(lambda(x)`(relabel ,lbs ,x)) (-1 1)))")

(defstrat mapstep@ (funstep &optional list list?)
  (when list
    (let ((step (funcall (eval funstep) (if list? list (car list))))
	  (rest (cdr list)))
      (then@ step
	     (mapstep@ funstep rest list?))))
  "[Extrategies] Sequentially applies FUNSTEP to each element of LIST. FUNSTEP is a function
in Lisp that takes one argument and returns a proof command. After each application of FUNSTEP,
the resulting proof command is applied to the first branch. When LIST? is nil, the argument of
FUNSTEP represents the head of the list at each iteration. If LIST? is t, the argument of FUNSTEP
represents the complete list at each iteration. See (help mapstep) for examples of use.")

(defun enlist-bindings (bindings)
  (let ((bndgs (enlist-it bindings)))
    (if (listp (car bndgs)) bndgs (list bndgs))))

(defhelper with-fresh-labels-tccs__ (ftccs)
  (mapstep #'(lambda(x)`(tccs-formula* ,(car x) :label ,(cadr x))) ftccs)
  "[Extrategies] Internal strategy." "")

(defhelper with-fresh-labels__ (bindings thn steps)
  (when steps
    (let ((bindgs   (enlist-bindings bindings))
	  (vlbs     (mapcar #'(lambda(x)(list (car x) (list 'quote (freshlabel (string (car x))))))
			    bindgs))
	  (ftccs    (loop for b in bindgs
			  for opt = (cddr b)
			  when (or (equal (car opt) ':tccs)
				   (and (equal (car opt) ':tccs?)
					(cadr opt)))
			  collect (let* ((tccs (format nil "*~a-tccs*" (car b)))
					 (lccs (freshlabel tccs)))
				    (list (car b) lccs (intern tccs :pvs) (list 'quote lccs)))))
	  (vtccs    (mapcar #'(lambda (tcc) (cddr tcc)) ftccs))
	  (vrs      (append vlbs vtccs))
	  (ltccs    (mapcar #'cadr ftccs))
	  (labs     (mapcar #'car bindgs))
	  (plabs    (set-pairing
		     (loop for b in bindgs
			   when (cadr b)
			   collect (car b))))
	  (fnums    (loop for b in bindgs
			  for fnum = (cadr b)
			  when fnum
			  collect fnum))
	  (thenstep (cons thn steps))
	  (step     `(let ,vrs (then (relabel ,plabs ,fnums)
				     (with-fresh-labels-tccs__$ ,ftccs)
				     (try ,thenstep (skip) (fail))
				     (delabel ,labs)
				     (delete ,ltccs)))))
      step))
  "[Extrategies] Internal strategy." "")

(defstrat with-fresh-labels (bindings &rest steps)
  (else (with-fresh-labels__$ bindings then steps) (skip))
  "[Extrategies] Creates fresh labels and binds them to formulas
specified in BINDINGS.  Then, sequentially applies STEPS to all
branches. All created labels are removed before the strategy
exits. BINDINGS has either the form (VAR [FNUMS]) or ((VAR1 [FNUMS1
[OPT1]]) ...  (VARn [FNUMSn [OPTn]])). Optional information OPTi can
be either :tccs or :tccs?  t|nil. The option :tccs? nil behaves as if
no option is provided.  In the other cases, TCCs of FNUMSi are added
as hypotheses to the sequent by applying (tccs-formula FNUMi) before
STEPS. The TCCs formulas of FNUMi are automatically labeled using a
new label denoted by the implicit variable *VARi-tccs*. The strategy
removes all added hypotheses before exiting.

For example,

(with-fresh-labels 
  ((l 1) (m -1 :tccs)) 
  (inst? l :where m))

creates fresh labels, which are denoted by the variables l and m, and
issues the proof command (label l 1), (label m -1), and (tccs-formula
m). Then, the strategy instantiates formula l with matches from
formula m. Finally, it removes all added hypotheses and labels.")

(defstrat with-fresh-labels@ (bindings &rest steps)
  (else (with-fresh-labels__$ bindings then@ steps) (skip))
  "[Extrategies] Creates fresh labels and binds them to formulas specified in BINDINGS. 
Then, sequentially applies STEPS to the main branch. Created labels are removed before 
ending. BINDINGS are specified as in WITH-FRESH-LABELS.")

(defhelper with-fresh-names__ (bindings thn steps)
  (when steps
    (let ((bindgs   (enlist-bindings bindings))
	  (vnms     (mapcar #'(lambda(x)(list (car x) (freshname (string (car x)))))
			    bindgs))
	  (vlbs     (loop for b in bindgs
			  when (cadr b)
			  collect (let ((v (format nil "*~a*" (car b))))
				    (list (intern v :pvs) 
					  (list 'quote (freshlabel (string (car b))))))))
	  (nmsexs   (loop for b in bindgs
			  for v in vnms
			  when (cadr b)
			  append (list (cadr v) (cadr b))))
	  (ftccs    (loop for b in bindgs
			  for opt = (cddr b)
			  when (cadr b)
			  collect (when (or (equal (car opt) ':tccs)
					    (and (equal (car opt) ':tccs?)
						 (cadr opt))
					    (and (equal (car opt) ':tcc-step)
						 (cadr opt)))
			  (let ((va (format nil "*~a-tccs*" (car b)))
				(la (format nil "~a-tccs" (car b))))
				      (list (intern va :pvs) (list 'quote (freshlabel la)))))))
	  (vtccs    (remove-if-not #'identity ftccs))
	  (tccstp   (when vtccs
		      (set-pairing
		       (loop for b in bindgs
			     for opt = (cddr b)
			     when (cadr b)
			     collect (cond ((or (equal (car opt) ':tccs)
						(and (equal (car opt) ':tccs?)
						     (cadr opt))) '(extra-tcc-step))
					   ((equal (car opt) ':tcc-step) (cadr opt)))))))
	  (wfn      (freshlabel "wfn"))
	  (wfn-tccs (freshlabel "wfc-tccs"))
	  (lbtccs   (mapcar #'car ftccs))
	  (plbtccs  (when vtccs (set-pairing (pair-lists (list wfn-tccs) lbtccs nil t))))
	  (vrsnms   (append vnms vlbs vtccs))
	  (thenstep (cons thn steps))
	  (lbvrs    (mapcar #'car vlbs))
	  (plbvrs   (set-pairing (pair-lists (list wfn) lbvrs nil t)))
	  (allbs    (cons wfn (cons wfn-tccs (append lbtccs lbvrs))))
	  (step     `(let ,vrsnms (then (then@ (name-label* ,nmsexs :hide? t :label ,plbvrs
							    :tcc-label ,plbtccs :tcc-step ,tccstp)
					       (try ,thenstep (skip) (fail)))
					(reveal ,wfn)
					(replaces ,wfn :dir rl)
					(delete ,wfn ,wfn-tccs)
					(touch (delabel ,allbs :hidden? t))))))
      step))
  "[Extrategies] Internal strategy." "")

(defstrat with-fresh-names (bindings &rest steps) (else
  (with-fresh-names__$ bindings then steps) (skip)) 
  "[Extrategies] Creates fresh names and binds them to expressions
 specified in BINDINGS.  Then, sequentially applies STEPS to all
 branches. All created names are expanded before the strategy
 exits. BINDINGS has either the form (VAR [EXPR]) or ((VAR1 [EXPR1
 [OPT1]]) ...  (VARn [EXPRn [OPTn]])). Optional information OPTi can
 be either :tccs, :tccs? t|nil, or :tcc-step TCC-STEP. The option
 :tccs? nil behaves as if no option is provided.  In the other cases,
 TCCs of EXPRi are added as hypotheses to the sequent by applying
 (tccs-expression EXPRi) before STEPS. These TCCs are discharged by a
 default strategy or by TCC-STEP, if one is provided.  The TCCs
 formulas of EXPRi are automatically labeled using a new label denoted
 by the implicit variable *VARi-tccs*.  For all 1 <= i <= n, an
 implicit variable *VARi* is defined such that it denotes the label of
 the formula introduced by (name VARi EXPRi). The strategy removes all
 added labels and hypotheses before exiting.


For example,

(with-fresh-names 
  ((e \"x+2\") (f \"sqrt(x)\" :tccs)) 
  (inst 1 e f))

creates fresh names e and f, and issues the proof commands (name e
\"x+2\"), (name f \"sqrt(x)\"), and (tccs-expression \"sqrt(x)\").
Then, the strategy instantiates formula 1 with the expressions denoted
by e and f. Finally, it expands names e and f and removes all added
hypotheses and labels.")

(defstrat with-fresh-names@ (bindings &rest steps)
  (else (with-fresh-names__$ bindings then@ steps) (skip))
  "[Extrategies] Creates fresh names and binds them to expressions
specified in BINDINGS.  Then, sequentially applies STEPS to the main
branch. BINDINGS are specified as in WITH-FRESH-NAMES.")

;;; Copying formulas

(defhelper copy__ (fn label labels?)
  (let ((labs (extra-get-labels-from-fnum fn)))
    (then (discriminate (copy fn) label)
	  (when labels?
	    (relabel labs label))
	  (hide label)))
  "[Extrategies] Internal strategy." "")

(defstep copy* (fnums &optional label hide? labels?)
  (let ((fs      (extra-get-fnums fnums))
	(labcpy  (or label (freshlabel "cpy")))
	(qlabcpy (list 'quote labcpy))
	(qlabels (list 'quote labels?)))
    (then
     (mapstep #'(lambda (x)`(copy__$ ,x ,qlabcpy ,qlabels)) fs)
     (unless hide? (reveal labcpy))
     (unless label (delabel labcpy))))
  "[Extrategies] Copies formulas in FNUMS. The copied formulas are labeled LABEL(s), if
LABEL is not nil. When HIDE? is t, the copied formulas are hidden. If LABELS? is t,
labels are also copied."
  "Copying formulas ~a")

(defstep protect (fnums step &optional label hide?)
  (if fnums
      (let ((labprc (or label (freshlabel "prc"))))
	(with-fresh-labels
	 (!pro fnums)
	 (copy* !pro labprc :hide? t :labels? t)
	 step
	 (unless hide? (reveal labprc))
	 (unless label (delabel labprc))))
    step)
  "[Extrategies] Protects formulas FNUMS so that they are not afected by STEP. The protected formulas
 are labeled LABEL(s), if LABEL is not nil."
  "Protecting formulas in ~a")

;;; Defining tactics

(defhelper localtactic__ (nm stratn step)
  (if (check-name stratn)
      step
    (printf "Local strategy ~a is not defined in this proof context" nm))
  "[Extrategies] Internal strategy." "")

(defrule deftactic (nm arg_or_step &optional step)
  (let ((stratn  (format nil "local_tactic_~a__" nm))
	(arg     (when step arg_or_step))
	(stp     (list 'localtactic__ nm stratn (or step arg_or_step)))
	(doc1    (format nil "Local tactic ~a defined in the proof context: ~a"
			 nm (label *ps*)))
	(doc2    (format nil "Applying local tactic ~a" nm)))
    (then (lisp (defstep nm arg stp doc1 doc2)) 
	  (if (check-name stratn)
	      (printf "Redefining local tactic ~a" nm)
	    (then (name stratn "TRUE")
		  (delete -1)))))
  "[Extrategies] Defines a tactic named NM. A tactic is a strategy that is local to the current branch
of the proof. NM needs to be a valid identifier in PVS. A tactic definition can be either
(deftactic NM STEP) or (deftactic NM (ARGUMENTS) STEP). For example,

(deftactic myfirsttactic (then (flatten) (assert) (grind)))

defines a tactic (myfirsttactic) that sequentially applies (flatten),
(assert), and (grind). Tactics can be parametric, for example

(deftactic mysecondtactic (fnums) (then (flatten) (assert fnums) (grind)))

defines a tactic (mysecondtactic <fnum>), where <fnum> is a parameter provided by the user,
that sequentially applies (flatten), (assert <fnum>), and (grind). Parameters can be
optional and have a default value, for example,

(deftactic mythirdtactic (&optional (fnums *)) (then (flatten) (assert fnums) (grind)))

defines a tactic that behaves as (myfirsttactic) when used without parameters, e.g.,
(mythirdtactic), and as (mysecondtactic <fnum>) when used with a parameter, e.g.,
(mythirdtactic <fnum>)."
  "Defining local tactic ~a")

;; This strategy enables the addition of trusted formulas into the current sequent.
;; Examples of such additions are type-checking information (TCCs), ground evaluations,
;; and external trusted oracles. The strategy MUST only be used in proof rules.

(defun trust! (orcl stamp)
  #'(lambda (ps)
      (let* ((torcl (is-trusted-oracle orcl)))
	(cond ((and torcl stamp
		    (equal stamp
			   (car (get-stack torcl))))
	       (unless (get-internal torcl)
		 (format t "Trusted oracle: ~a." orcl))
	       (values '! nil nil))
	      (t
	       (values 'X nil nil))))))

(addrule 'trust! (orcl stamp) ()
	 (trust! orcl stamp)
	 "Trusts oracle ORCL with STAMP. This strategy *must* only be used in proof rules."
	 "")

(defstrat trust (orcl step &optional steps)
  (let ((steps (if (equal steps '!) (list steps) steps))
	(torcl (is-trusted-oracle orcl)))
    (if torcl
	(let ((stamp (get-universal-time))
	      (xxx   (push stamp (get-stack torcl)))
	      (mrcl  `(trust! ,orcl ,stamp))
	      (stps  (mapcar #'(lambda (x) (or (and (equal x '!) mrcl) x)) steps)))
	  (unwind-protect$
	   (try-branch step stps (skip))
	   (sklisp (pop (get-stack torcl)))))
      (printf "~a is not a trusted oracle" orcl)))
  "This strategy enables the addition of trusted formulas into the current sequent.
Examples of such additions are type-checking information (TCCs), ground evaluations,
and external *trusted* oracles. The strategy *must* only be used in proof rules.")

;;; TCCs -- The following rules extend the internal proving capabilities of PVS.
;;; They cannot be written as a combination of the basic proof rules

(defstrat extra-tcc-step ()
  (then (assert) (subtype-tcc))
  "Tries to prove TCCs by first using (assert) and then (subtype-tcc)")

(defhelper relabel-hide__ (step lab1 lab2 hide?)
  (then step
	(relabel lab1 lab2)
	(when hide?
	  (hide lab2)))
  "[Extrategies] Internal strategy." "")

(defun get-tccs-expression (expr)
  (when expr
    (let ((*tccforms* nil)
	  (*generate-tccs* 'all))
      (pc-typecheck (pc-parse (format nil "~a" expr) 'expr))
      (reverse (mapcar #'tccinfo-formula *tccforms*)))))
  
(defhelper tccs-expression__ (expr label hide? tcc-step)
  (let ((e    (extra-get-expr expr))
	(estr (expr2str e)))
    (when e
      (with-fresh-labels
       (!tce)
       (relabel-hide__ (discriminate (typepred! estr :all? t :implicit? t) !tce)
		       label !tce hide?)
       (let ((tccs  (get-tccs-expression e))
	     (tcc   (when tccs (expr2str (mk-conjunction tccs)))))
	 (when tccs
	   (trust *PVSTypechecker*
		  (discriminate (case tcc) !tce)
		  ((relabel-hide__ (flatten -1) label !tce hide?)
		   (finalize tcc-step) !)))))))
  "[Extrategies] Internal strategy." "")

(defrule tccs-expression (expr &optional label hide? (tcc-step (extra-tcc-step)))
  (when tcc-step
    (tccs-expression__$ expr label hide? tcc-step))
  "[Extrategies] Adds TCCs of expression EXPR as hypotheses to the current sequent. Added hypotheses
are labeled LABEL(s), if LABEL is not nil. They are hidden when HIDE? is t. TCCs generated during
the execution of the command are discharged with the proof command TCC-STEP. If TCC-STEP is nil,
the strategy does nothing."
  "Adding TCCs of expression ~a as hypotheses")

(defhelper tccs-formula__ (fn)
  (let ((tccs  (get-tccs-expression (extra-get-formula-from-fnum fn)))
	(tcc   (when tccs (expr2str (mk-conjunction tccs)))))
    (when tccs
      (trust *PVSTypechecker*
	     (case tcc)
	     ((flatten -1) !))))
  "[Extrategies] Internal strategy." "")

(defhelper tccs-formula*__ (fnums)
  (with-fresh-labels
   (!tcf fnums)
   (let ((fs1 (extra-get-fnums !tcf)))
     (when fs1
       (all-implicit-typepreds !tcf)
       (let ((fs2 (extra-get-fnums !tcf)))
	 (mapstep #'(lambda(x)`(tccs-formula__$ ,x)) fs2)))))
  "[Extrategies] Internal strategy." "")

(defrule tccs-formula* (&optional (fnums *) label hide?)
  (with-fresh-labels
   (!tcfs)
   (discriminate (tccs-formula*__$ fnums) !tcfs)
   (relabel-hide__ (skip) label !tcfs hide?))
  "[Extrategies] Adds TCCs of formulas FNUMS as hypotheses to the current sequent. Added hypotheses
are labeled LABEL(s), if LABEL is not nil. They are hidden when HIDE? is t."
  "Adding TCCs of formulas ~a as hypotheses")

(defstep tccs-formula (&optional (fnum 1) label hide?)
  (tccs-formula* fnum label hide?)
  "[Extrategies] Adds TCCs of formula FNUM as hypotheses to the current sequent. Added hypotheses
are labeled LABEL(s), if LABEL is not nil. They are hidden when HIDE? is t."
  "Adding TCCs of formula ~a as hypotheses")

(defhelper tccs-step__ (step label hide?)
  (with-fresh-labels
   ((!tcs)
    (!tcl))
   (trust
    *PVSTypechecker*
    (with-labels step !tcs t)
    ((let ((parent (parent-proofstate *ps*))
	   (tccs   (loop for goal in (remaining-subgoals parent)
			 append (select-seq (s-forms (current-goal goal)) !tcs)))
	   (fms    (mapcar #'formula tccs))
	   (expr   (when fms (expr2str (mk-conjunction fms)))))
       (when expr
	 (trust *PVSTypechecker*
		(discriminate (case expr) !tcl)
		((relabel-hide__ (flatten !tcl) label !tcl hide?)
		 (delete !tcs) !)))) !)))
  "[Extrategies] Internal strategy." "")

(defrule tccs-step (step &optional label hide?)
  (tccs-step__$ step label hide?)
  "[Extrategies] If STEP generates subgoals, e.g., TCCs, these subgoals are added as hypotheses to the
first subgoal. Added hypotheses are labeled LABEL(s), if LABEL is not nil. They are hidden when
HIDE? is t."
 "Adding TCCs of step ~a as hypotheses")

(defstep with-tccs (step &optional steps (fnums *) (tcc-step (extra-tcc-steps)))
  (let ((stps (append (or steps '((skip))) (cons 'finalize tcc-step))))
    (with-fresh-labels
     (!wtccs fnums :tccs)
     (branch step stps)))
  "[Extrategies] Applies STEP after introducing TCCs for the formulas in FNUMS. If STEP generates
subgoals, these subgoals are consecutively discharged using STEPS, which is a list of steps.
TCCs generated during the execution of the command are discharged with the proof command TCC-STEP."
  "Applying ~a assumings TCCs")
	     
;;; Control flow

(defhelper finalize__ (step)
  (try step (fail) (skip))
  "[Extrategies] Internal strategy." "")

(defstrat finalize (step)
  (else (finalize__$ step) (skip))
  "[Extrategies] Either finishes the current goal with STEP or does nothing.")

(defstep touch (&optional (step (skip)))
  (else step (case "TRUE"))
  "[Extrategies] Does step and touches the proof context so that try and else consider that step
does something, even when it doesn't." "Doing ~a and touching the proof context")

(defstrat when (flag &rest steps)
  (if (and flag steps)
      (let ((step (cons 'then steps)))
	step)
    (skip))
  "[Extrategies] Behaves as (if FLAG (then STEP1 ... STEPn) (skip)). Due to the execution model
of strategies in PVS, FLAG must be a variable.")

(defstrat when@ (flag &rest steps)
  (if (and flag steps)
      (let ((step (cons 'then@ steps)))
	step)
    (skip))
  "[Extrategies] Behaves as (if FLAG (then@ STEP1 ... STEPn) (skip)). Due to the execution model
of strategies in PVS, FLAG must be a simple variable.")

(defstrat unless (flag &rest steps)
  (if (and (not flag) steps)
      (let ((step (cons 'then steps)))
	   step)
      (skip))
  "[Extrategies] Behaves as (if (not FLAG) (then STEP1 ... STEPn) (skip)). Due to the
execution model of strategies in PVS, FLAG must be a simple variable.")

(defstrat unless@ (flag &rest steps)
  (if (and (not flag) steps)
      (let ((step (cons 'then@ steps)))
	   step)
      (skip))
  "[Extrategies] Behaves as (if (not FLAG) (then@ STEP1 ... STEPn) (skip)). Due to
the execution model of strategies in PVS, FLAG must be a simple variable.")

(defhelper when-label__ (label step)
  (let ((fs (extra-get-fnums label)))
    (when fs step))
  "[Extrategies] Internal strategy." "")

(defstrat when-label (label &rest steps)
  (let ((qlabl (list 'quote label)))
    (mapstep #'(lambda(x)`(when-label__$ ,qlabl ,x)) steps))
  "[Extrategies]  Sequentially applies STEPS to all branches as long as at least one formula
is labeled LABEL in the sequent.")

(defhelper unless-label__ (label step)
  (let ((fs (extra-get-fnums label)))
    (unless fs step))
  "[Extrategies] Internal strategy." "")

(defstrat unless-label (label &rest steps)
  (let ((qlabl (list 'quote label)))
    (mapstep #'(lambda(x)`(unless-label__$ ,qlabl ,x)) steps))
  "[Extrategies]  Sequentially applies STEPS to all branches as long as no formula is labeled
as LABEL in the sequent.")

(defstrat if-label (label then-step &optional (else-step (skip)))
  (if (extra-get-fnums label)
      then-step else-step)
  "[Extrategies]  Applies THEN-STEP if at least one formula is labeled LABEL in the current
sequent; otherwise, applies ELSE-STEP.")

(defhelper for__ (n step)
  (if (numberp n)
      (if (<= n 0)
	  (skip)
	(let ((m (- n 1)))
	  (then step
		(for__$ m step))))
    (unless n
     (repeat* step)))
  "[Extrategies] Internal strategy." "")

(defstep for (n &rest steps)
  (when steps
    (let ((step (cons 'then steps)))
      (for__$ n step)))
  "[Extrategies] Iterates N times STEP1 ... STEPn, or until it does nothing if N is nil,
along all the branches."
  "Iterating ~1@*~a ~@*~a times along all the branches")

(defhelper for@__ (n step)
  (if (numberp n)
      (if (<= n 0)
	  (skip)
	(let ((m (- n 1)))
	  (then@
	   step
	   (for@__$ m step))))
    (unless@ n
     (repeat step)))
  "[Extrategies] Internal strategy." "")

(defstep for@ (n &rest steps)
  (when steps
    (let ((step (cons 'then@ steps)))
      (for@__$ n step)))
  "[Extrategies] Iterates N times STEP1 ... STEPn, or until it does nothing if N is nil,
along the first branch."
  "Iterating ~1@*~a ~@*~a times along the first branch")

;; Skolem, let-in, let-def

(defun skeep-formula (fn expr)
  (or (and (< fn 0) (exists-expr? expr))
      (and (> fn 0) (forall-expr? expr))))

(defun is-binding-in-subs (bnd i n subs)
  (or (member (id  bnd) subs
	      :test #'(lambda (x y) (and (not (numberp (car y)))
					 (string= x (car y)))))
      (member i subs :test 
	      #'(lambda (x y) (and 
			       (numberp (car y))
			       (or (equal x (car y))
				   (equal x (+ 1 n (car y)))))))))
      
(defun select-skeep-names (bindings subs)
  (let ((n (length bindings)))
    (loop for bnd in bindings
	  for i from 1
	  for is = (is-binding-in-subs bnd i n subs)
	  collect (or (cadar is) '_))))

(defun select-skeep-bindings (bindings but)
  (let ((n (length bindings)))
    (loop for bnd in bindings
	  for i from 1
	  unless (is-binding-in-subs bnd i n but)
	  collect bnd)))

(defun skeepname (prefix &optional type but)
  (when *current-context*
    (if (is-freevar prefix type but)
	prefix
      (let ((midfix (if type "!" "_")))
	(loop for i from 1
	      for nn = (format nil "~a~a~a" prefix midfix i)
	      when (is-freevar nn type but)
	      return nn)))))

(defun skeepnames (names &optional types but)
  (when names
    (let ((nn (skeepname (car names) (car types) but)))
      (cons nn  (skeepnames (cdr names) (cdr types) (cons nn but))))))

(defstep skeep (&optional (fnum (+ -)) preds? postfix but)
  (let ((postfix (or postfix ""))
	(fnexpr  (first-formula fnum :test #'skeep-formula))
    	(fn      (car fnexpr))
	(expr    (cadr fnexpr)))
    (when fnexpr
      (let ((but    (mapcar #'enlist-it (enlist-it but)))
	    (bndgs  (select-skeep-bindings (bindings expr) but))
	    (nnames (skeepnames
		     (mapcar #'(lambda(x) (format nil "~a~a" (id x) postfix)) bndgs)
		     (mapcar #'type bndgs)
		     (mapcar #'cadr but)))
	    (names  (if but (select-skeep-names 
			     (bindings expr)
			     (append (mapcar #'(lambda (x y)(list (id x) y)) bndgs nnames) but))
		      nnames)))
	(then (skolem fn names preds?)
	      (flatten)))))
   "[Extrategies] Skolemizes a universally quantified formula in FNUM, using the names
of the bounded variables as the names of the skolem constants. If POSTFIX is provided, it 
is appended to the variable names. Names that clash with other names in the current
sequent are replaced by fresh names. Type predicates are introduced as hypothesis when 
PREDS? is t.

BUT is a list of variable references of the form <VAR> or (<VAR> <NAME>), where <VAR> is either 
a quantified variable name or a relative position of a variable in the quantifier (positive means 
left to right, negative means right to left). If <NAME> is not provided, the variable referred to 
by <VAR> will be excluded from the skolemization. If <NAME> is provided, it is used as the name of 
the skolem constant for the variable <VAR>.  For example, (skeep :but \"x\") skolemizes all variables 
but excludes \"x\", (skeep :but (\"x\" (\"y\" \"YY\"))) skolemizes all variables but \"x\" and 
uses \"YY\" as the name of the skolem constant for \"y\"." 
   "Skolemizing and keeping names of the universal formula in ~a")

(defstep skeep* (&optional (fnum '*) preds? postfix n)
  (with-fresh-labels (!skp fnum)
	      (for@ n (skeep !skp :preds? preds? :postfix postfix)))
  "[Extrategies] Iterates N times skeep (or until it does nothing if N is nil) in a universally 
quantified formula in FNUM. If POSTFIX is provided, it is appended to the names of the bounded 
variables. Names that clash with other names in the current sequent are replaced by fresh 
names. Type predicates are introduced as hypothesis when PREDS? is t."
  "Iterating skeep in ~a")

(defun insteep-formula (fn expr)
  (or (and (> fn 0) (exists-expr? expr))
      (and (< fn 0) (forall-expr? expr))))

(defun select-insteep-exprs (bindings subs postfix)
  (let ((n (length bindings)))
    (loop for bnd in bindings
	  for i from 1
	  for is = (is-binding-in-subs bnd i n subs)
	  collect (if is (or (extra-get-expstr (cadar is) nil) '_)
		    (format nil "~a~a" (id bnd) postfix)))))

(defstep insteep (&optional (fnum (+ -)) postfix but)
  (let ((postfix (or postfix ""))
	(fnexpr  (first-formula fnum :test #'insteep-formula))
    	(fn      (car fnexpr))
	(expr    (cadr fnexpr)))
    (when fnexpr
      (let ((but   (mapcar #'enlist-it (enlist-it but)))
	    (exprs (select-insteep-exprs (bindings expr) but postfix))
	    (stp   (cons 'inst (cons fn exprs))))
	stp)))
  "[Extrategies] Instantiates an existentially quantified formula in FNUM, using the names
of the bounded variables. If POSTFIX is provided, it is appended to the variable names. 

BUT is a list of variable references of the form <VAR> or (<VAR> <EXPR>), where <VAR> is either 
a quantified variable name or a relative position of a variable in the quantifier (positive means 
left to right, negative means right to left). If <EXPR> is not provided, the variable referred to 
by <VAR> will be excluded from the instantiation. If <EXPR> is provided, <VAR> is instantiated with
<EXPR>. For example, (insteep :but \"x\") instantiates all variables using the names of the quantified
formula but excludes \"x\", (insteep :but (\"x\" (\"y\" \"100\"))) instantiates all variables but 
\"x\" and instantiates \"\y\" with \"100\"."
  "Instantiating with the names of the existential formula in ~a")

(defstep insteep* (&optional (fnum '*) postfix n)
  (with-fresh-labels (!instp fnum)
	      (for@ n (insteep !instp :postfix postfix)))
  "[Extrategies] Iterates N times insteep (or until it does nothing if N is nil) in an
existentially quantified formula in FNUM.  If POSTFIX is provided, it is appended to the 
names of the bounded variables."
  "Iterating insteep in ~a")

(defhelper skoletin__ (fn expr name nth var postfix hide? tcc-step old)
  (let ((flabels (extra-get-labels-from-fnum fn))
	(consq   (> fn 0))
	(ret     (make-ret))
	(nexpr   (sigmared expr name nth 
			   :newnames (enlist-it var)
			   :postfix postfix :ret ret))
	(retexpr (ret-expr ret))
	(flag    (not (numberp nexpr)))
	(casestr (when flag (format nil "~a" nexpr))))
    (when flag
      (with-fresh-labels
       ((!skl fn :tccs)
	(!skd)
	(!old))
       (try-branch
	(discriminate (name-label* retexpr :fnums nil :dir rl :tcc-step tcc-step) !old)
	((then (branch (discriminate (case casestr) !skd)
		       ((if consq (then (replaces !old :hide? nil) (beta (!skl !skd)))
			  (then (when old (hide !old) (reveal !old))
				(beta !skd :let-reduce? nil)))
			(if consq (then (when old (hide !old) (reveal !old))
					(beta !skd :let-reduce? nil))
			  (then (replaces !old :hide? nil) (beta (!skl !skd))))
			(then (replaces !old :hide? nil) (finalize tcc-step))))
	       (relabel flabels !skd)
	       (delete !skl)
	       (if hide?
		   (hide !old)
		 (unlabel !old)))
	 (then (replaces !old :hide? nil)
	       (delete !skl)
	       (finalize (assert))))
	(skip)))))
  "[Extrategies] Internal strategy." "")

(defun skoletin-formula (fn expr)
  (let-expr? expr))

(defstep skoletin (&optional (fnum (+ -)) name (nth 1) var postfix hide?
			     (tcc-step (extra-tcc-step)) old?)
  (let ((postfix (or postfix ""))
	(fnexpr  (or (first-formula fnum :test #'skoletin-formula)
		     (first-formula fnum)))
    	(fn      (car fnexpr))
	(expr    (cadr fnexpr)))
    (when fnexpr
      (skoletin__$ fn expr name nth var postfix hide? tcc-step old?)))
  "[Extrategies] Names the NTH occurrence (left-right, depth-first) of
NAME in a let-binding of the form
   LET ...,NAME = <expr>,... IN <e>
in FNUM and introduces the equality <var>=expr as hypothesis. All occurrences
of NAME in <e> are replaced by <var>. By default, <var> is NAME, with a POSTFIX
if provided. An explicit name can be provided using the option VAR. Names that
clash with other names in the current sequent are replaced by fresh names.

If NAME is nil, the name of the NTH let-in binding is chosen by the strategy.
In this case, if the NTH let-in binding is an expression (<x1>,...,<xn>) = <expr>,
the equalities <var1>=<expr>`1,...,<varn>=<expr>`n are introduced to the sequent.
By default, <vari> is <xi>. Explicit names can be provided using the
option VAR as a list (<var1> ... <varm>), where m <= n. In this list,
if <vari> is _, <xi> is used instead of <vari>.

Name definitions are hidden when HIDE? is t; they can be recalled at any time with
the command (reveal \"<name>:\"), where <name> is one of the names introduced by the
strategy. TCCs generated during the execution of the command are discharged with the
proof command TCC-STEP.

CAVEAT: The order in which formulas are introduced by skoletin in version 6.0 is different
from previous versions. The option OLD? reproduces the old order. 

NOTE: This command works better when all let-in variables are explicitly typed as in
LET x:posreal = 2 IN 1/x."
  "Naming let-in binding in ~a")

(defstep skoletin* (&optional (fnum *) postfix hide? (tcc-step (extra-tcc-step)) n old?)
  (with-fresh-labels
   (!sks fnum)
   (for@ n (skoletin !sks :postfix postfix :hide? hide? :tcc-step tcc-step :old? old?)))
  "[Extrategies] Iterates N times skoletin (or until it does nothing if N is nil) in FNUM.

CAVEAT: The order in which formulas are introduced by skoletin in version 6.0 is different
from previous versions. The option OLD? reproduces the old order."
  "Naming let-in bindings in ~a")

(defhelper redlet__ (fn expr name nth tcc-step)
  (let ((flabels (extra-get-labels-from-fnum fn))
	(nexpr   (sigmared expr name nth))
	(flag    (not (numberp nexpr)))
	(casestr (when flag (format nil "id(~a)" nexpr))))
    (when flag
      (with-fresh-labels
       ((!rdl fn :tccs)
	(!rdd))
       (branch (discriminate (case casestr) !rdd)
	       ((then
		 (expand "id" !rdd :assert? none)
		 (if (> fn 0)
		    (beta (!rdl !rdd))
		  (beta !rdd :let-reduce? nil)))
		(then
		 (expand "id" !rdd :assert? none)
		 (if (< fn 0)
		     (beta (!rdl !rdd))
		   (beta !rdd :let-reduce? nil)))
		(finalize tcc-step)))
       (relabel flabels !rdd)
       (delete !rdl))))
  "[Extrategies] Internal strategy." "")

(defstep redlet (&optional (fnum (+ -)) name (nth 1) (tcc-step (extra-tcc-step)))
  (let ((fnexpr (or (first-formula fnum :test #'skoletin-formula)
		    (first-formula fnum)))
    	(fn     (car fnexpr))
	(expr   (cadr fnexpr)))
    (when fnexpr
      (redlet__$ fn expr name nth tcc-step)))
  "[Extrategies] Reduces the NTH occurrence of NAME (left-right, depth-first) in a let-in expression
in FNUM. If NAME is nil, the NTH name is reduced instead. TCCs generated during the execution of the
command are discharged with the proof command TCC-STEP.

NOTE: This command works better when all let-in variables are explicitly typed as in LET x:posreal = 2
IN 1/x."
  "Reducing let-in expression in ~a")

(defstep redlet* (&optional (fnum *) (tcc-step (extra-tcc-step)) (n 1))
  (with-fresh-labels
   (!rds fnum)
   (for@ n (redlet !rds :tcc-step tcc-step)))
  "[Extrategies] Iterates N times redlet (or until it does nothing if N is nil). TCCs generated during
the execution of the command are discharged with the proof command TCC-STEP."
  "Reducing let-in expressions in ~a")

(defhelper skodef__ (fnum expr name var postfix hide? tcc-step)
  (let ((names (mapcar #'(lambda(x) (format nil "~a" (id x)))
		       (bindings expr)))
	(flag  (or (not name)
		   (member name names :test #'string=)))
	(nve   (when flag (carands (if (< fnum 0)
				       (args1 (expression expr))
				     (expression expr))
				   names name var postfix)))
	(n     (nth 0 nve))
	(v     (nth 1 nve))
	(e     (nth 2 nve))
	(lv    (format nil "~a:" v))
	(cases (format nil "(~a=~a) IFF TRUE" v e))
	(ivr   (instvar v n (length names))))
    (when nve
      (with-fresh-labels
       (!skk fnum :tccs)
       (try-branch
	(name-label v e :fnums nil :dir rl :hide? t)
	((branch (let ((stp (cons 'inst (cons !skk ivr))))
		   stp)
		 ((branch (case-replace cases)
			  ((then
			    (delete -1)
			    (unless hide? (reveal lv) (delabel lv)))
			   (then (reveal lv) (finalize (assert (lv 1))))
			   (finalize tcc-step)))
		  (finalize tcc-step)))
	 (finalize tcc-step))
	(skip)))))
  "[Extrategies] Internal strategy." "")

(defun skodef-formula (fnum expr)
  (or (and (< fnum 0)
	   (forall-expr? expr)
	   (implication? (expression expr)))
      (and (> fnum 0)
	   (exists-expr? expr))))

(defstep skodef (&optional (fnum (+ -)) name var postfix hide? (tcc-step (extra-tcc-step)))
  (let ((postfix (or postfix ""))
	(fnexpr  (first-formula fnum :test #'skodef-formula))
    	(fn      (car fnexpr))
	(expr    (cadr fnexpr)))
    (when fnexpr
      (skodef__$ fn expr name var postfix hide? tcc-step)))
  "[Extrategies] Given a antecedent formula FNUM of the form
   FORALL(..,NAME:<type>,..) : NAME=<expr> AND ... IMPLIES ...
or a consequent formula FNUM of the form
   EXISTS (..,NAME:<type>,..) : NAME=<expr> AND ...,
this strategy introduces a name definition <var>=expr as hypothesis and
instantiates NAME in FNUM with <var>. By default, <var> is NAME, with
a POSTFIX if provided. An explicit name can be provided using the option VAR.
Names that clash with other names in the current sequent are replaced by
fresh names. 

Name definitions are hidden when HIDE? is t; they can be recalled at any
time with the command (reveal \"<name>:\"), where <name> is the name
introduced by the strategy. TCCs generated during the execution of the command
are discharged with the proof command TCC-STEP."
  "Instantiating a quantifier in ~a with a name definition")

(defstep skodef* (&optional (fnum *) hide? postfix (tcc-step (extra-tcc-step)) n)
  (with-fresh-labels
   (!skk fnum)
   (for@ n (skodef !skk :postfix postfix :hide? hide? :tcc-step tcc-step)))
  "[Extrategies] Iterates N times skodef (or until it does nothing if N is nil) in FNUM.
TCCs generated during the execution of the command are discharged with the proof command TCC-STEP."
  "Iterating skodef in ~a")

;;; Splitting and splashing

(defstep cut (cases &optional (tcc-step (extra-tcc-step)))
  (let ((cases (enlist-it cases)))
    (when cases
      (let ((expr   (extra-get-expstr (car cases)))
	    (expest (cdr cases)))
	(branch (case expr)
		((cut$ expest tcc-step)
		 (skip)
		 (finalize tcc-step))))))
  "[Extrategies] The proof command (cut (<e1> ... <en>)) behaves as (case <e1> ... <en>).
TCCs generated during the execution of the command are discharged with the proof command TCC-STEP."
  "Cutting formula(s) in ~a")

(defun select-ands (ands order &optional result)
  (if order
      (let* ((n (car order))
	     (a (cond ((> n 0)
		       (nth (1- n) ands))
		      ((and (< n 0)
			    (< (abs n) (length ands)))
		       (nth (+ (length ands) n) ands)))))
	(select-ands ands (cdr order) (append result (enlist-it a))))
    result))

(defhelper splash__ (fn formula reverse order tcc-step)
  (let ((gands   (get-ands-expr formula (> fn 0)))
	(ands    (when (> (length gands) 1)
		   (if order (select-ands gands (enlist-it order)) gands)))
	(rands   (if reverse (reverse ands) ands)))
    (when rands
      (with-fresh-labels
       ((!spl fn :tccs)
	(!spd))
       (let ((cases (mapcar #'expr2str rands)))
	 (branch (discriminate (cut cases :tcc-step tcc-step) !spd)
		 ((assert (!spl !spd))
		  (delete !spl)))))))
  "[Extrategies] Internal strategy." "")

(defun splash-formula (fn expr)
  (or (and (< fn 0) (or (implication? expr) (disjunction? expr)))
      (and (> fn 0) (conjunction? expr))))

(defstep splash (&optional (fnum *) reverse? order (tcc-step (extra-tcc-step)))
  (let ((fnexpr (first-formula fnum :test #'splash-formula))
	(fn     (car fnexpr))
	(expr   (cadr fnexpr)))
    (when fnexpr
      (splash__$ fn expr reverse? order tcc-step)))
  "[Extrategies] Asymmetrically splits a (-)-disjunctive or (+)-conjunctive formula in FNUM.
The direction of the split is reversed when REVERSE? is t (this may generate unprovable TCCs
since Boolean operators in PVS are non-strict.) Particular components of the formula can be
specified in ORDER, which is a list of integers (i1 .. in). An integer ik represents the ik-th
component of the formula, left to right if ik is positive, right to left if ik is negative.
TCCs generated during the execution of the command are discharged with the proof command TCC-STEP."
  "Splashing formula in ~a")

;;; Miscellaneous

(defstep replaces (&optional (fnums -) (in *) but from to
			     (hide? t) (dir lr))
  (let ((flist (extra-get-fnums fnums))
	(nfrom (extra-get-fnum from))
	(nto   (extra-get-fnum to))
	(feqs  (remove-if #'(lambda (x) (= x 0))
			  (cond ((and from to) (fromto nfrom nto))
				(from (remove-before nfrom flist))
				(to   (remove-after nto flist))
				(t    flist)))))
    (when feqs
      (let ((labreq (freshlabels "req" (length feqs)))
	    (plabs  (set-pairing labreq))
	    (qdir   (list 'quote dir))
	    (qhide  (list 'quote hide?))
	    (forms  (extra-get-but-fnums but :all in)))
	(with-fresh-labels
	 (!rep forms)
	 (let ((qrep (list 'quote !rep)))
	   (then
	    (relabel plabs feqs)
	    (mapstep #'(lambda(x)`(try (replace ,x ,qrep :dir ,qdir)
				       (when ,qhide
					 (unlabel* ,x ,qrep)
					 (delabel ,x :hide? t))
				       (skip)))
		     labreq)
	    (delabel labreq)))))))
  "[Extrategies] Iterates the proof command replace to rewrite with the formulas in FNUMS,
respecting the order, the formulas in IN but not in BUT. The keys DIR and HIDE? are like
in REPLACE. Notice that in contrast to REPLACE, the default value of HIDE? is T. Instead
of using FNUMS, rewriting formulas can be addressed via FROM and TO."
  "Iterating replace")

(defstep rewrites (lemmas-or-fnums &optional (fnums *) (target-fnums *) (dir lr) (order in) dont-delete?)
   (let ((lms    (enlist-it lemmas-or-fnums))
	 (qdir   (list 'quote dir))
	 (qorder (list 'quote order))
	 (qdont  (list 'quote dont-delete?)))
     (with-fresh-labels ((!rew fnums)
		  (!ret target-fnums))
		 (let ((qrew (list 'quote !rew))
		       (qret (list 'quote !ret)))
		   (mapstep@ #'(lambda (x)`(rewrite ,x :fnums ,qrew :target-fnums ,qret
						    :dir ,qdir :order ,qorder :dont-delete? ,qdont))
			     lms))))
   "[Extrategies] Rewrites with a list of lemmas or fnums. LEMMAS-OR-FNUMS has the form
(LEMMAS-OR-FNUMS1 ... LEMMAS-OR-FNUMS). Options are as in rewrite."
  "Rewriting with ~a")

(defstep rewrite* (lemmas-or-fnums &optional (fnums *) (target-fnums *) (dir lr) (order in) dont-delete?)
   (let ((lms    (enlist-it lemmas-or-fnums))
	 (qdir   (list 'quote dir))
	 (qorder (list 'quote order))
	 (qdont  (list 'quote dont-delete?)))
     (with-fresh-labels ((!rws fnums)
		  (!rwt target-fnums))
		  (let ((qrws (list 'quote !rws))
			(qrwt (list 'quote !rwt)))
		    (repeat
		     (mapstep@ #'(lambda (x)`(rewrite ,x :fnums ,qrws :target-fnums ,qrwt
						      :dir ,qdir :order ,qorder :dont-delete? ,qdont))
			       lms)))))
   "[Extrategies] Recursively rewrites LEMMAS-OR-FNUMS on the first branch. Options are as in rewrites."
   "Rewriting recursively with ~a")

(defun quantified-formula (fn expr)
  (or (exists-expr? expr) (forall-expr? expr)))

(defun get-suffices-expr (expr estr conseq forall var qn &optional (n 1) b)
  (let ((thisq (or (and (null var) (null qn) 
			(not (if forall
				 (forall-expr? (expression expr))
			       (exists-expr? (expression expr)))))
		   (and (null var) (equal n qn))))
	(thisv (and var
		    (or (null qn) (eq n qn))
		    (position var (bindings expr)
			      :test #'(lambda (x y) (string= x (id y)))))))
    (if (or thisq (equal thisv (1- (length (bindings expr)))))
	(format nil "~:[NOT ~;~]~:[EXISTS~;FORALL~]~{(~{~a~^,~})~}:~a ~a (~a)"
		conseq forall (append b (list (bindings expr)))
		estr
		(if forall "IMPLIES" "AND")
		(expression expr))
      (if thisv
	  (format
	   nil
	   "~:[NOT ~;~]~:[EXISTS~;FORALL~]~{(~{~a~^,~})~}:~a ~a ~:[EXISTS~;FORALL~](~{~a~^,~}):~a"
	   conseq forall (append b (list (subseq (bindings expr) 0 (1+ thisv))))
	   estr
	   (if forall "IMPLIES" "AND")
	   forall (subseq (bindings expr) (1+ thisv))
	   (expression expr))
	(when (and (or (null qn)
		       (< n qn))
		   (if forall (forall-expr? (expression expr))
		     (exists-expr? (expression expr))))
	  (get-suffices-expr (expression expr) estr conseq forall
			     var qn (1+ n)
			     (append b (list (bindings expr)))))))))

(defstep suffices (fnum expr &optional after-var after-qn (tcc-step (extra-tcc-step)))
  (let ((estr   (extra-get-expstr expr nil))
	(fnexpr (when estr (first-formula fnum :test #'skeep-formula)))
    	(fn     (car fnexpr))
	(expr   (cadr fnexpr))
	(form   (when expr (get-suffices-expr expr estr (> fn 0) (forall-expr? expr)
					      after-var after-qn))))
    (when form
      (with-fresh-labels 
       (!sff fn :tccs)
       (branch (case form)
	       ((skip)
		(delete !sff)
		(finalize tcc-step))))))
  "[Extrategies] Introduces a sufficient hypothesis EXPR to a universally quantified formula
in FNUM. If FNUM is in the consequent, it is expected to have the form FORALL(<vars>):<expr>;
if FNUM is in the antecedent it is expected to have the form EXISTS(<vars>):<expr>. In the
first case, the resulting formula has the form FORALL(<vars>):EXPR IMPLIES <expr>. In the
second case, the resulting formula has the form EXISTS(<vars>): EXPR AND <expr>. The hypothesis
EXPR is added after the quantified variable AFTER-VAR, if provided, and/or after the AFTER-QN-th
quantifier, if provided."
  "Introducing a sufficient hypothesis to formula ~a")

(defstrat extrategies-about ()
  (let ((version    *extrategies-version*)
	(strategies *extrategies*)) 
    (printf "%--
% ~a
% http://shemesh.larc.nasa.gov/people/cam/Extrategies
% Strategies in Extrategies:~a
%--~%" version strategies))
  "[Extrategies] Prints Extrategies's about information.")

;;; EXPERIMENTAL EXTRATEGIES

;;; Induction

(defhelper inductionfree__ (recvar &optional first)
  (let ((name (freshname "V"))
	(pre  (car (eval-ext-expr `(! * (-> ,recvar)))))
	(term (when pre (format nil "~a" (ee-pvs-obj pre)))))
    (if term
	(branch (name-replace name term :hide? t)
		((inductionfree__$ name)
		 (skip)))
      (unless
       first
       (typepred recvar))))
  "[Extrategies] Internal strategy." "")

(defstrat inductionfree (&optional (recvar "v"))
  (if (forall-expr? (extra-get-formula 1))
      (let ((recvar (format nil "~a!1" recvar)))
	(then (skosimp* :preds? t)
	      (repeat (inductionfree__$ recvar t))
	      (assert)))
    (then
     (repeat (inductionfree__$ recvar t))
     (assert)))
  "[Extrategies] Extracts induction free principle from definition of recursive function. RECVAR is the
name of the quantified variable that encodes the recursive call.")

;;;;; SPECIFIC FUNCTIONS ;;;;; 

;; Used in splash for extracting conjuctive expressions in the consequent

(defun extra-conjunction (expr)
  (or (conjunction? expr)
      (is-function-expr expr '(AND &))))

(defun extra-disjunction (expr)
  (or (disjunction? expr)
      (is-function-expr expr '(OR))))

(defun extra-negation (expr)
  (or (negation? expr)
      (is-function-expr expr '(NOT))))

(defun extra-implication (expr)
  (or (implication? expr)
      (is-function-expr expr '(IMPLIES =>))))

;; Get list of conjunctions (disjunctions when is-and is false)
(defun get-ands-expr (expr &optional (is-and t))
  (cond ((or (and is-and (extra-conjunction expr))
             (and (not is-and) (extra-disjunction expr)))
	 (append (get-ands-expr (args1 expr) is-and)
		 (get-ands-expr (args2 expr) is-and)))
	((and (not is-and) (extra-implication expr))
	 (append (get-ands-expr (args1 expr) t)
		 (get-ands-expr (args2 expr) nil)))
	(is-and (list expr))
	(t      (list (if (extra-negation expr) (args1 expr)
			(mk-negation expr))))))

;; Given an expression of the form a => (b = > c), return the list
;; (c a b), where the first element is the thesis and the other members of the
;; list are the hypotheses.
(defun get-hypotheses (expr)
  (if (implication? expr)
      (let ((h (get-hypotheses (args2 expr))))
	(cons (car h) (append 
		       (get-ands-expr (args1 expr))
		       (cdr h))))
    (list expr)))

(defun make-exprs (names expr n)
  (when names (cons (format nil "(~a)`~a" expr n)
		    (make-exprs (cdr names) expr (+ n 1)))))

(defun carands (ands names name var postfix)
  (cond ((conjunction? ands)
	 (or (carands (args1 ands) names name var postfix)
	     (carands (args2 ands) names name var postfix)))
	((and (equation? ands) (name-expr? (args1 ands)))
	 (let ((nm (format nil "~a" (id (args1 ands)))))
	   (when (or (not name) (string= nm name))
	     (let ((p (position nm names :test #'string=)))
	       (when p
		 (list (+ p 1)
		       (freshname (or var (format nil "~a~a" nm postfix)))
		       (format nil "~a" (args2 ands))))))))))

(defun instvar (v k n)
  (loop for i from 1 to n
	collect (if (eq k i) v '_)))

(defun merge-let-names (names newnames postfix)
  (when names
    (cond ((and newnames (string= (car newnames) '_))
	   (cons (format nil "~a~a" (car names) postfix)
		 (merge-let-names (cdr names) (cdr newnames) postfix)))
	  (newnames 
	   (cons (car newnames) 
		 (merge-let-names (cdr names) (cdr newnames) postfix)))
	  (t (mapcar #'(lambda (x) (format nil "~a~a" x postfix))
		     names)))))

;; Used in skoletin to return an expression
(defstruct ret expr)

(defun sigmared-list (exprs name n l &key newnames postfix ret)
  (if exprs
      (let ((e (sigmared (car exprs) name n :newnames newnames
			 :postfix postfix :ret ret)))
	(if (numberp e)
	    (sigmared-list (cdr exprs) name n (append l (list (car exprs)))
			   :newnames newnames :postfix postfix :ret ret)
	  (append l (cons e (cdr exprs)))))
    n))
  
(defun sigmared (expr name n &key newnames postfix ret)
  (cond
   ((<= n 0) n)
   ((let-expr? expr)
    (let* ((namexpr (argument expr))
	   (e       (sigmared namexpr name n :newnames newnames
			      :postfix postfix :ret ret)))
      (if (numberp e)
	  (let* ((names   (mapcar  #'(lambda(x) (format nil "~a" (id x)))
				   (bindings (operator expr))))
		 (onevar  (not (cdr names)))
		 (types   (mapcar #'(lambda(x) (if (dep-binding? x) (type x) x))
				      (if onevar
					  (list (domain (type (operator expr))))
					(types (domain (type (operator expr)))))))
		 (letexpr (expression (operator expr)))
		 (typelet (range (type (operator expr))))
		 (m       (if (or (not name) (member name names
						     :test #'string=))
			      (- e 1)
			    e)))
	    (cond ((and (= m 0) (or onevar (not name)))
		   ;; Let-in single variable or
		   ;; Let-in any name
		   (let*
		       ((mergenames (when ret (skeepnames
					       (merge-let-names names
								newnames  
								postfix))))
			(newnamexpr (if ret (format nil "~{~a~^,~}" mergenames)
				      namexpr))
			(newexprs   (when ret
				      (cond (onevar (list namexpr))
					    ((tuple-expr? namexpr)
					     (exprs namexpr))
					    (t (make-exprs names namexpr 1)))))
			(strexprs   (mapcar #'(lambda(x)(format nil "~a" x))
					    newexprs))
			(newtypes   (merge2str names types :conc ":" :sep ","))
			(lbdapp     (format nil "(LAMBDA (~a):~a)(~a)"
					    newtypes letexpr newnamexpr))
			(pcexpr     (pc-parse lbdapp 'expr)))
		     (progn 
		       (when ret (setf (ret-expr ret)
				       (merge-lists mergenames
						    strexprs)))
		       (setf (type pcexpr) (type expr))
		       pcexpr)))
		  ((= m 0)
		   ;; Let-in multiple variable, reducing one variable
		   (let*
		       ((p     (position name names :test #'string=))
			(prj   (if (tuple-expr? namexpr)
				   (format nil "~a" (nth p (exprs namexpr)))
				   (format nil "~a`~a" namexpr (+ p 1))))
			(mergename (when ret
				     (freshname (if newnames (car newnames)
						  (format nil "~a~a"
							  name postfix)))))
			(newnamexpr (if ret mergename prj))
			(lbdapp (format nil "(LAMBDA (~a:~a):~a)(~a)"
					name (nth p types)
					letexpr newnamexpr))
			(nexpr (pc-parse lbdapp 'expr))
			(dummy (setf (type nexpr) typelet))
			(nargs (if (tuple-expr? namexpr)
				   (format nil "~{~a~^,~}" (removepos p (exprs namexpr)))
				 (merge2str (list namexpr) 
					    (removepos
					     p (fromto 1 (length names)))
					    :conc "`" :sep ",")))
			(argexpr (pc-parse (format nil "(~a)" nargs) 'expr))
			(typetup (copy (type namexpr)
				   'types
				   (removepos p (types (type namexpr))))))
		     (progn
		       (when ret (setf (ret-expr ret) (list mergename prj)))
		       (setf (type argexpr) typetup)
		       (copy expr
			     'argument
			     argexpr
			     'operator
			     (copy (operator expr)
				   'expression nexpr
				   'type
				   (copy (type (operator expr))
					 'domain
					 (copy (domain (type
							(operator expr)))
					       'types
					       (removepos p types)))
				   'bindings
				   (removepos p (bindings
						 (operator expr))))))))
		  (t ;; Recursion
		   (let ((f (sigmared letexpr name m :newnames newnames
				      :postfix postfix :ret ret)))
		     (if (numberp f) f
		       (copy expr 'operator
			     (copy (operator expr)
				   'expression f)))))))
	(copy expr 'argument e))))
   ((infix-application? expr)
    (let ((e (sigmared (args1 expr) name n :newnames newnames
		       :postfix postfix :ret ret)))
      (if (numberp e)
	  (let ((f (sigmared (args2 expr) name e :newnames newnames
			     :postfix postfix :ret ret)))
	    (if (numberp f) f
	      (copy expr 'argument
		    (copy (argument expr)
			  'exprs
			  (list (args1 expr) f)))))
	(copy expr 'argument
	      (copy (argument expr)
		    'exprs
		    (list e (args2 expr)))))))
   ((unary-application? expr)
    (let ((e (sigmared (argument expr) name n :newnames newnames
		       :postfix postfix :ret ret)))
      (if (numberp e) e
	(copy expr 'argument e))))
   ((tuple-expr? expr)
    (let ((e (sigmared-list (exprs expr) name n nil :newnames newnames
			    :postfix postfix :ret ret)))
      (if (numberp e) e
	(copy expr 'exprs e))))
   (t n)))


;;;; From interval_arith

;;
;; This file is part of a generic framework to define branch & bound strategies.
;;

(defparameter *ia-builtin* '(("sq" "SQ")
			     ("abs" "ABS")
			     ("+" "ADD")
			     ("-" "SUB")
			     ("*" "MULT")
			     ("/" "DIV")
			     ("^" "POW")
			     ("TRUE" "BCONST(TRUE)")
			     ("FALSE" "BCONST(FALSE)")
			     ("NOT" "BNOT")
			     ("AND" "BAND")
			     ("&" "BAND")
                             ("OR" "BOR")
			     ("IMPLIES" "BIMPLIES")
			     ("=>" "BIMPLIES")
			     (">" "REL(>)")
			     (">=" "REL(>=)")
			     ("<" "REL(<)")
			     ("<=" "REL(<=)")
			     ("=" "EQ")
			     ("##" "BINCLUDES")))

;; Every element in *ia-extended* has the form (<f> <F>), where <F> is either <F>, for
;; rational functions, or (<F> <n>) for approximated ones. It is expected that these functions
;; satisfy the inclusion and fundamental theorems of interval arithmetic.
(defparameter *ia-extended* '(("sqrt" ("SQRT_n"))
			      ("pi" ("PI_n")) 
			      ("sin" ("SIN_n"))
			      ("cos" ("COS_n"))
			      ("tan" ("TAN_n"))
			      ("atan" ("ATAN_n"))
			      ("ln" ("LN_n"))
			      ("exp" ("EXP_n"))
			      ("e" ("E_n"))
                              ("floor" "FLOOR")
			      ("mod" "MOD")))

(defparameter *ia-excluded* '("Tan?" "[||]"))

(defparameter *ia-let-names* nil)

(defun ia-get-vars-from-expr (expr &optional subs)
  (get-vars-from-expr expr
		      (append (mapcar #'car subs)
			      (mapcar #'car *ia-extended*))))

;; Find unbounded vars (vars is a list of variable names) 
(defun ia-find-unbound-vars (vars)
  (loop for v in vars
	when (let ((xv (gethash v *extra-varranges*)))
	       (or (null xv) (null (xterval-lb xv)) (null (xterval-ub xv))))
	collect v))

(defun ia-complete-vars (vars morevars)
  (let ((vars (remove-if-not 
	       #'(lambda(x)(member (extra-var-name x) morevars :test #'string=)) vars)))
    (append vars
	    (loop for v in morevars
		  unless (member v vars
				 :test #'(lambda (x y) (string= x (extra-var-name y))))
		  collect v))))

(defun ia-var-intervals (vars)
  (loop for v in vars
	for xv = (gethash v *extra-varranges*)
	collect (format nil "[|~a,~a|]" (xterval-lb xv) (xterval-ub xv))))

;; Form a string representing the box of variables vars
(defun ia-box (vars)
  (if vars
      (format nil "(: ~{~a~^,~} :)" (ia-var-intervals vars))
    "(::)"))

;; Is id in subs?
(defun ia-idsubs? (id subs)
  (car (member id subs
	       :test #'(lambda (x y) (string= x (car y))))))

;; Form a string representing an interval expression of expr, where
;;   - n      : approximation parameter
;;   - var    : list of variables
;;   - subs   : list of substitutions of the general form (<f> (<F> <n>) <arity>)
;; Output:
;;   - Expr such that eval(expr,vars) ## Eval(Expr,box)
(defun ia-interval-expr (expr n vars &optional subs)
  (setq *ia-let-names* nil)
  (catch '*ia-error*
    (ia-interval-expr-rec expr n vars
			  (append subs *ia-builtin* *ia-extended*)
			  (check-name "IntervalStrategies__"))))

(defun ia-approx-n (n nn)
  (if nn (max (+ n nn) 0) n))

(defun ia-error (msg)
  (throw '*ia-error* (list msg)))

(defun ia-format-local-var (vl n)
  (let ((posvar (+ n (1- (length vl)))))
    (if (is-number-type (cdar vl))
	(format nil "X(~a)" posvar)
      (format nil "POS?(X(~a))" posvar))))

(defun ia-interval-expr-rec (expr n vars subs extended &optional localvars)
  (let ((val (when (or (is-number-type (type expr)) (is-bool-type (type expr)))
	       (typecheck (extra-add-evalexpr expr)))))
    (cond ((and val (is-number-type  (type val)))
	   (format nil "r2E(~a)" val))
	  ((and val (is-bool-type (type val)))
	   (format nil "b2B(~a)" val))
	  ((is-const-decl-expr expr (mapcar #'car subs)) ;; Is a constant, but not a rational one
	   (let ((opl (ia-idsubs? (expr2str expr) *ia-extended*))) ;; Check if extended import is required.
	     (when (and opl (not extended))
	       (ia-error (format 
			  nil
			  "Theory interval_arith@strategies needs to be imported to support constant ~a"
			  expr))))
	   ;; At this point, imported chain is OK. 
	   (let ((opl (ia-idsubs? (expr2str expr) subs)))
	     (if opl
		 (let ((op (cadr opl)))
		   (if (listp op)
		       (format nil "~a(~a)" (car op) (ia-approx-n n (nth 1 op)))
		     (format nil "~a" op)))
	       (ia-error (format nil "Don't know how to translate constant ~a" expr)))))
	  ((is-variable-expr expr)
	   (let ((vl (when (name-expr? expr)
		       (member (id expr) localvars :test #'(lambda(x y) (equal x (car y)))))))
	     (if vl (ia-format-local-var vl (length vars))
	       (let ((vl (member (expr2str expr) vars :test #'string=)))
		 (if vl
		     (format nil "X(~a)" (- (length vars) (length vl)))
		   (ia-error (format nil "Don't know how to translate variable ~a" expr)))))))
	  ((and (unary-application? expr)
		(is-function-expr expr "-"))
	   (format nil "NEG(~a)"
		   (ia-interval-expr-rec (args1 expr) n vars subs extended localvars)))
	  ((is-function-expr expr "^")
	   (format nil "POW(~a,~a)"
		   (ia-interval-expr-rec (args1 expr) n vars subs extended localvars)
		   (args2 expr)))
	  ((is-function-expr expr "##")
	   (let ((val (extra-add-evalexpr (args2 expr))))
	     (if (record-expr? val)
		 (format nil "BINCLUDEX(~a,~a)"
			 (ia-interval-expr-rec (args1 expr) n vars subs extended localvars)
			 val)
	       (ia-error (format nil "Don't know how to translate expression ~a" (args2 expr))))))
	  ((if-expr? expr)
	   (if (is-bool-type (type expr))
	       (format nil "BITE(~a,~a,~a)"
		       (ia-interval-expr-rec (nth 0 (arguments expr)) n vars subs extended localvars)
		       (ia-interval-expr-rec (nth 1 (arguments expr)) n vars subs extended localvars)
		       (ia-interval-expr-rec (nth 2 (arguments expr)) n vars subs extended localvars))
	     (ia-error (format nil "IF-THEN-ELSE construct ~a is unsupported" expr))))
	  ((let-expr? expr)
	   (if (or (is-bool-type (type expr)) (is-number-type (type expr)))
	       (let* ((op  (operator expr))
		      (typ (domain (type op))))
		 (if (or (is-number-type typ) (and (is-bool-type (type expr))
						   (is-bool-type typ)))
		     (let* ((vt  (cons (id (car (bindings op))) typ))
			    (xm  (ia-interval-expr-rec (argument expr) n vars subs extended localvars))
			    (nm  (freshname (format nil "V_~a" (length *ia-let-names*)))))
		       (setq *ia-let-names* (append *ia-let-names* (list (cons nm xm))))
		       (format nil "~:[~;B~]LETIN(~a,~a)" (is-bool-type (type expr)) nm
			       (ia-interval-expr-rec (expression op) n vars subs extended
						     (cons vt localvars))))
		   (ia-error (format nil "LET-IN construct ~a is unsupported" expr))))
	     (ia-error (format nil "LET-IN construct ~a is unsupported" expr))))
	  ((arg-tuple-expr? expr)
	   (format nil "~{~a~^,~}"
		   (mapcar #'(lambda(x)(ia-interval-expr-rec x n vars subs extended localvars))
			   (exprs expr))))
	  ((is-function-expr expr)
	   (let ((opl (ia-idsubs? (id (operator expr)) (cdr *ia-extended*))))
	     (when (and opl (not extended))
	       (ia-error (format 
			  nil
			  "Theory interval_arith@strategies needs to be imported to support function ~a"
			  (id (operator expr))))))
	   (let ((opl (ia-idsubs? (id (operator expr)) subs)))
	     (if opl 
		 (let ((op (cadr opl)))
		   (if (listp op)
		       (format nil "~a(~a)(~a)"
			       (car op) (ia-approx-n n (nth 1 op))
			       (ia-interval-expr-rec (args1 expr) n vars subs extended localvars))
		     (format nil "~a(~a)" op
			     (ia-interval-expr-rec (argument expr) n vars subs extended localvars))))
	       (ia-error (format nil "Don't know how to translate function ~a" (id (operator expr)))))))
	  (t (ia-error (format nil "Don't know how to translate expression ~a" expr))))))

(defhelper interval-eq__ (names fnum &optional subs nohide)
  (let ((excl (append
	       *ia-excluded*
	       (mapcar #'car *ia-builtin*) 
	       (mapcar #'car *ia-extended*)
	       (mapcar #'car subs))))
    (with-fresh-labels
     (!ieq fnum)
     (apply (repeat (expand "length" !ieq)))
     (apply (repeat (expand names !ieq)))
     (expand ("X" "r2E" "b2B") !ieq)
     (apply (repeat (expand "list2array" !ieq)))
     (apply (repeat (then (expand "beval" !ieq)(expand "realexpr?")(expand "eval" !ieq))))
     (expand "##")
     (flatten)
     (assert)
     (protect (^ !ieq) (then (hide-all-but (!ieq nohide))
			     (grind :exclude excl)))
     (assert)))
  "[Interval] Internal strategy." "")

(defhelper vars-sharp__ ()
  (then
   (expand* "##" "contains?")
   (rewrite* ("abs_lt" "abs_le" "ge_abs" "gt_abs"))
   (flatten)
   (assert))
  "[Interval] Internal strategy." "")

(defhelper vars-in-box__ ()
  (then
   (apply (repeat (expand "list2array" 1)))
   (rewrite "vars_in_box")
   (apply (repeat (expand "length" 1)))
   (apply (repeat (expand "vars_in_box_rec" 1)))
   (vars-sharp__$))
  "[Interval] Internal strategy." "")

(defmacro req-ths-names (req-ths)
  `(if (or (not ,req-ths)
	   (stringp (first ,req-ths)))
       ,req-ths
     (let ((fst (first ,req-ths)))
       (if (listp fst) fst (list fst)))))

(defmacro req-ths-errormsg (req-ths)
  `(if (all-strings ,req-ths)
       (format nil "At least one of the following theories are required by the strategy: ~{~a~^,~}" (first ,req-ths))
     (second ,req-ths)))

(defmacro all-strings (req-ths)
  `(every #'stringp ,req-ths))

(defmacro validate-required-theories (req-ths)
  `(and (listp ,req-ths)
       (or (all-strings ,req-ths)
	   (and (all-strings (first ,req-ths))
		(cond ((= (length ,req-ths) 2)
		       (stringp (second ,req-ths)))
		      ((> (length ,req-ths) 2)
		       nil)
		      (t t))))))


(defun ia-is-true-output (ans)
  (and (is-function-expr ans "Some")
       (extra-is-true (argument ans))))

(defun ia-is-false-output (ans)
  (and (is-function-expr ans "Some")
       (extra-is-false (argument ans))))

;; *** Generic branch and bound strategies (interval and numerical) by Mariano Moscato

;; -------------------------------------------------------------------------- ;;
(defhelper gbandb_interval__ (required-theories
			      pvsexpr-to-strobj
			      bandb-function-name
			      soundness-lemma-name
			      rewrite-decls
			      beval-solver
			      &optional 
			      (fnums 1) (precision 3) maxdepth sat?
			      vars 
			      subs 
			      dirvar
			      verbose?
			      label
			      (equiv? t)
			      (tccs? t))
  (let ((name     (freshname "iar"))
	(label    (or label (freshlabel name)))
	(fns      (extra-get-fnums fnums))
	(fn       (if (= (length fns) 1) (car fns) 0))
	(expr     (when fns
		    (if (equal fn 0)
			(mk-disjunction (mapcar #'formula (extra-get-seqfs fns)))
			(extra-get-formula-from-fnum fn))))
	(quant    (cond ((forall-expr? expr) 1)
			((exists-expr? expr) -1)
			(t 0))) ;; forall: quant > 0, exists: quant < 0, none: 0
	(fms      (append (mapcar #'(lambda (f) (extra-get-formula-from-fnum f))
				  (extra-get-fnums `(-^ ,fnums)))
			  (mapcar #'(lambda (f) 
				      (make-negation
				       (extra-get-formula-from-fnum f)))
				  (extra-get-fnums `(+^ ,fnums)))))
	(qexpr    (when (/= quant 0) (lift-predicates-in-quantifier expr (list *real*))))
	(andexprs (when expr
		    (cond ((< quant 0) 
			   (get-ands-expr (expression qexpr)))
			  ((> quant 0) 
			   (cdr (get-hypotheses (expression qexpr))))
			  ((and (= quant 0) (< fn 0))
			   (get-ands-expr expr))
			  ((and (= quant 0) (> fn 0))
			   (cdr (get-hypotheses expr))))))
	(ia-expr  (if (= quant 0) expr (expression qexpr)))
	(qvars    (when (/= quant 0)
		    (mapcar #'(lambda (x) (format nil "~a" (id x))) (bindings qexpr))))
	;; qvars has quantified variables
	(vars     (ia-complete-vars
		   (enlist-it vars)
		   (if (/= quant 0) ;; Quantifier
		       ;; Only consider variables in the quantifier
		       qvars
		     ;; Consider all variables in the expression
		     (ia-get-vars-from-expr ia-expr subs))))
	;; vars has user provided variables + quantified variables
	(initeqs (extra-reset-evalexprs))
	(ia-vars (extra-get-var-ranges
		  (if (/= quant 0) ;; Quantifier
		      ;; Only consider ranges in the quantifier
		      andexprs
		    ;; Consider all ranges
		    (append andexprs fms))
		  vars))
	;; ia-vars is just like vars but only names
	(unvars  (ia-find-unbound-vars ia-vars))
	(tccs?   (and tccs? (not sat?)))
	(msg     (cond ((null expr)
			(format nil "Formula ~a not found" fnums))
		       ((and sat? (null ia-vars))
			(format nil "Formula ~a doesn't seem to have variables. It cannot be checked for satisfiability" fnums))
		       ((not (validate-required-theories required-theories))
			(format nil 
				"Error in param: required-theories should have the form ((<th_1 name> ... <th_n name>) <error msg>) or (<th_1 name> ... <th_n name>)"))
		       ((and
			 (req-ths-names required-theories)
			 (notany (lambda (thname) (check-name thname)) (req-ths-names required-theories)))
			  (req-ths-errormsg required-theories))
		       (unvars
			(format nil "Variable~:[~;s~] ~{~a~^,~} ~:[is~;are~] unbounded."
				(cdr unvars) unvars (cdr unvars))))))
    (if msg
	(printf msg)
      (let ((findcex   (if sat? (<= quant 0) (< (* fn quant) 0)))
	    (neg       (if sat? (<= quant 0) (or (< quant 0) (and (= quant 0) (< fn 0)))))
	    (nname     (if neg (format nil "BNOT(~a)" name) name))
	    (ia-box    (ia-box ia-vars))
	    (ia-iexpr  (funcall pvsexpr-to-strobj ia-expr precision ia-vars subs))
	    (names     (append (mapcar #'car *ia-let-names*) (list name)))
	    (exprs     (append (mapcar #'cdr *ia-let-names*) (list ia-iexpr)))
	    (namexprs  (merge-lists names exprs))
	    (ia-dirvar (or dirvar "alt_max"))
	    (maxdepth  (cond ((null ia-vars) 0)
			     (maxdepth maxdepth)
			     (findcex 10)
			     (t 100)))
	    (ia-eval   (format nil "~a(~a,~a,~:[TRUE~;FALSE~])(~a,~a)"
			       bandb-function-name
			       maxdepth ia-dirvar findcex nname ia-box))
	    (msg       (when (listp ia-iexpr) (car ia-iexpr))))
	(if msg
	    (printf msg)
	  (with-fresh-labels@
	   (!ia fnums :tccs? tccs?)
	   (spread
	    (name-label* namexprs :hide? t :tcc-step (then (hide !ia) (extra-tcc-step)))
	    ((try-branch
	      (eval-expr ia-eval :safe? nil)
	      ((then
		(relabel label -1)
		(let ((output  (args2 (extra-get-formula -1)))
		      (splits  (get-expr-from-obj output 'splits))
		      (depth   (get-expr-from-obj output 'depth))
		      (answer  (get-expr-from-obj output 'ans 'answer))
		      (istrue  (ia-is-true-output answer))
		      (isfalse (ia-is-false-output answer))
		      (cex     (get-list-from-literal (get-expr-from-obj output 'ans 'counterex))))
		  (then
		   (when verbose? (printf "~%----"))
		   (if (and (not istrue) (not isfalse))
		       (then
			(printf "Formula cannot be proved nor disproved")
			(printf "Set MAXDEPTH or PRECISION to values greater than ~a AND ~a, respectively" 
				maxdepth precision))
		     (let ((prfex    (and cex findcex (/= quant 0) (not sat?))) ;; Existential proof
			   (prfall   (and istrue (not findcex) (not sat?)))     ;; Universal proof
			   (disprf   (and (if findcex istrue cex) (not sat?)))  ;; Disproof
			   (varvals  (if cex (merge-lists ia-vars cex)
				       (merge-lists ia-vars (ia-var-intervals ia-vars))))
			   (eqs      (extra-evalexprs))
			   (msg      (format nil
					     (if cex "~:[Formula~;Sequent~] ~@[~a ~]~a for ~{~a = ~a~^, ~}"
					       "~:[Formula~;Sequent~] ~@[~a ~]~a for any ~{~a ## ~a~^, ~}")
					     (or prfex prfall disprf)
					     (unless (or prfex prfall disprf) fnums)
					     (cond ((or prfex prfall) "holds")
						   (disprf "can be disproved")
						   ((and cex findcex) "is satisfiable")
						   (findcex "is not satisfiable")
						   (istrue "is valid")
						   (t "is invalid"))
					     varvals)))
		       (if (or prfex prfall) ;; Proof needs to be done
			   (then
			    (when verbose? (printf "~a~%Splits: ~a. Depth: ~a~%----~%" msg splits depth))
			    (let ((name soundness-lemma-name))
			      (lemma name))
			    (with-fresh-labels 
			     ((!ia-inst -1) (!ia-eqs))
			     (inst? !ia-inst)
			     (replaces label)
			     (beta !ia-inst)
			     (expand "sound?" !ia-inst)
			     (apply (repeat (expand "length" !ia-inst)))
			     (extra-evalexprs$ eqs !ia-eqs)
			     (branch (split !ia-inst)
				     ((if prfex ;; Existential proof
					  (let ((vs     (pairlis ia-vars cex))
						(instvs (mapcar 
							 #'(lambda (x)
							     (format nil "~a" 
								     (cdr (assoc x vs :test #'string=))))
							 qvars))
						(instp  (cons 'inst (cons !ia instvs))))
					    (then
					     (flatten)
					     (hide (-1 1))
					     instp
					     (eval-formula !ia :quiet? t)
					     (when equiv? 
					       (reveal !ia-eqs) 
					       (replaces !ia-eqs :hide? nil)
					       (beval-solver names 1 subs))
					     (eval-formula !ia)))
					;; Universal proof
					(let ((nqvars   (freshnames "x" (length qvars)))
					      (vs       (when nqvars (pairlis qvars nqvars)))
					      (skvs     (if nqvars
							    (mapcar #'(lambda (x)
									(cdr (assoc x vs :test #'string=))) 
								    ia-vars)
							  ia-vars))
					      (ia-lvars (format nil "list2array(0)((:~{~a~^, ~}:))" skvs)))
					  (then
					   (when nqvars (skolem !ia nqvars :skolem-typepreds? t))
					   (spread (inst !ia-inst ia-lvars)
						   ((when equiv? 
						      (reveal !ia-eqs) 
						      (replaces !ia-eqs :hide? nil)
						      (beval-solver   names !ia-inst 
								      subs *!ia-tccs*))
						    (if (null ia-vars)
							(eval-formula)
						      (then (flatten)
							    (reveal !ia-eqs) 
							    (replaces !ia-eqs :hide? nil)
							    (vars-in-box__$))))))))
				      (eval-formula)))))
			 (printf msg))))
		   (hide label)
		   (when verbose?
		     (printf "Splits: ~a. Depth: ~a" splits depth)
		     (printf "See hidden formulas labeled ~a for more information~%----~%" label)))))
	       (hide !ia))
	      (skip)))))))))
  "Checks if formulas FNUMS, which may be simply quantified, holds using the
algorithm called BANDB-FUNCTION-NAME. Its soundness must be guaranteed by
a lemma of name SOUNDNESS-LEMMA-NAME. BEVAL-SOLVER is the name of the
strategy that should be used to prove that the pvs expression corresponds
with the beval of the interval expr. REWRITE-DECLS are the rewriting
rules to be used as to simplify the evaluation expression.

REQUIRED-THEORIES is used to indicate the theories needed to be imported
in order to use the strategy. It should be a list of the form
((<th_1> ... <th_n>) <error msg>) or (<th_1> ... <th_n>) where every
th_i is a theory name and <error msg> is a custom error message.
The name of the function to translate a pvs expression to a string
representation of a ObjType is the parameter PVSEXPR-TO-STROBJ.

The parameter PRECISION indicates an accuracy of
10^-PRECISION in every atomic computation. However, this accuracy is
not guaranteed in the final result. MAXDEPTH is a maximum recursion
depth for the branch and bound algorithm.

If SAT? is set to t, the strategy checks if formula FNUMS,
whether in the antecedent or in the consequent, is satisfiable
and, in the positive case, prints a provably correct witness.
If formula FNUMS is quantified, it is checked for validity.

VARS is a list of the form (<v1> ... <vn>), where each <vi> is either a
variable name, e.g., \"x\", or a list consisting of a variable name and
an interval, e.g., (\"x\" \"[|-1/3,1/3|]\"). This list is used to specify
the variables in EXPR and to provide their ranges. If this list is not
provided, this information is extracted from the sequent.

SUBS is a list of substitutions for translating user-defined
real-valued functions into interval ones. Each substitution has
the form (<f> <F>), where <f> is the name of a real-valued function
and <F> is the name of its interval counterpart. It is assumed that
<F> satisfies the Inclusion and the Fundamental theorems of interval
arithmetic for <f>. Standard substitutions for basic arithmetic
operators, abs, sq, sqrt, trigonometric functions, exp, and ln
are already provided. This parameter can be used to change the precision
for a particular function, e.g., ((\"pi\" \"PI_n(4)\") (\"cos\"
(\"COS_n\" 1))(\"sin\" (\"SIN_n\" -1))) specifies the precision 4,
PRECISION+1, and PRECISION-1 for pi, cos, and sin, respectively.

DIRVAR is the name of a direction and variable selection method for
the branch an bound algorithm. Theory interval_bandb includes some
pre-defined methods. If none is provided, a choice is made base on the
problem.

If VERBOSE? is set to t, the strategy prints information about number of
splits, depth, etc. 

LABEL is used to label formulas containing additional information computed
by the branch and bound algorithm. These formulas are hidden, but they can
be brought to the sequent using the proof command REVEAL.

If EQUIV? is set to nil, the strategy doesn't try to prove that the
deep embedding of the original expression is correct. The proof of
this fact is trivial from a logical point of view, but requires
unfolding of several definitions which is time consuming in PVS.

If TCCs? is set to nil, the strategy doesn't try to prove possible
TCCs generated during its execution." "")

;; -------------------------------------------------------------------------- ;;
(defhelper gbandb_simple-numerical__ (pvsexpr-to-strobj
				      bandb-function-name
				      soundness-lemma-name
				      expr 
				      &optional
				      (precision 3)
				      (maxdepth 5))
  (let ((name    (freshname "sia"))
	(ia-expr (extra-get-expr expr))
	(ia-estr (expr2str ia-expr))
	(fms     (mapcar #'(lambda (fn) (extra-get-formula-from-fnum fn)) (extra-get-fnums '-)))
	(vars    (ia-get-vars-from-expr ia-expr))
	(ia-vars (extra-get-var-ranges fms vars))
	(unvars  (ia-find-unbound-vars ia-vars))
	(msg     (cond (unvars
			(format nil "Variable~:[~;s~] ~{~a~^, ~} ~:[is~;are~] unbounded."
				(cdr unvars) unvars (cdr unvars)))
		       ((null ia-expr)
			(format nil "Do not understand argument ~a." expr))
		       ((not (is-number-expr ia-expr))
			(format nil "Expresion ~a is not a real number expression." ia-expr))))
	(ia-box    (unless msg (ia-box ia-vars)))
	(ia-iexpr  (unless msg (funcall pvsexpr-to-strobj ia-expr precision ia-vars)))
	(maxdepth  (if (null ia-vars) 0 maxdepth))
	(ia-eval   (format nil "~a(~a,~a,~a)" bandb-function-name maxdepth name ia-box))
	(ia-lvars  (format nil "list2array(0)((:~{~a~^, ~}:))" ia-vars))
	(msg       (or msg (when (listp ia-iexpr) (car ia-iexpr)))))
    (if msg
	(printf msg)
      (spread
       (name-label name ia-iexpr :hide? t)
       ((try-branch
	 (eval-expr ia-eval :safe? nil)
	 ((then (lemma soundness-lemma-name)
		(inst? -1)
		(replaces -2)
		(beta -1)
		(expand "sound?" -1)
		(branch (split -1)
			((spread (inst -1 ia-lvars)
				 ((branch (invoke (case "%1 = %2") (! -1 1) ia-estr)
					  ((then (replaces -1)
						 (decimalize -1 precision))
					   (interval-eq__ name 1)
					   (then (hide -1)(vars-sharp__))))
				  (if (null ia-vars)
				      (eval-formula)
				    (vars-in-box__))))
			 (eval-formula))))
	  (skip))
	 (skip))))))
  "Computes a simple estimation of the minimum and maximum
values of EXPR using the algorithm called BANDB-FUNCTION-NAME. Its
soundness must be guaranteed by a lemma of name SOUNDNESS-LEMMA-NAME.
The name of the function translating a pvs expression to a string
representation of a ObjType is the parameter PVSEXPR-TO-STROBJ.

PRECISION is the number of decimals in the output
interval. PRECISION also indicates an accuracy of 10^-PRECISION in
every atomic computation. However, this accuracy is not guaranteed in
the final result.

MAXDEPTH is a maximum recursion depth for the branch and bound
algorithm.

This strategy is a simplified version of the more elaborated strategy
NUMERICAL." "")

;; -------------------------------------------------------------------------- ;;
(defhelper gbandb_numerical__ (required-theories   
			       pvsexpr-to-strobj   
			       bandb-function-name
			       soundness-lemma-name
			       expr 
			       &optional (precision 3) (maxdepth 10)
			       min? max?
			       vars 
			       subs
			       dirvar
			       verbose?
			       label
			       (equiv? t))
  (let ((name      (freshname "nml"))
	(label     (or label (freshlabel name)))
	(accuracy  (ratio2decimal (expt 10 (- precision)) nil precision))
	(ia-expr   (typecheck (extra-get-expr expr)))
	(ia-estr   (expr2str ia-expr))
	(fms       (append (mapcar #'(lambda (f) (extra-get-formula-from-fnum f))
				   (extra-get-fnums '-))
			   (mapcar #'(lambda (f) 
				       (make-negation
					(extra-get-formula-from-fnum f)))
				   (extra-get-fnums '+))))
	(vars      (ia-complete-vars (enlist-it vars) (ia-get-vars-from-expr ia-expr subs)))
	(initeqs   (extra-reset-evalexprs))
	(ia-vars   (extra-get-var-ranges fms vars))
	(unvars    (ia-find-unbound-vars ia-vars))
	(msg       (cond ((not (validate-required-theories required-theories))
			  (format nil "Error in param: required-theories should have the form ((<th_1 name> ... <th_n name>) <error msg>) or (<th_1 name> ... <th_n name>)"))
		         ((and
			   (req-ths-names required-theories)
			   (notany (lambda (thname) (check-name thname)) (req-ths-names required-theories)))
			  (req-ths-errormsg required-theories))
			 (unvars
			  (format nil "Variable~:[~;s~] ~{~a~^,~} ~:[is~;are~] unbounded."
				  (cdr unvars) unvars (cdr unvars)))
			 ((null ia-expr)
			  (format nil "Do not understand argument ~a." expr))
			 ((not (is-number-type (type ia-expr)))
			  (format nil "Expresion ~a is not a real number expression." ia-expr))))
	(ia-box    (unless msg (ia-box ia-vars)))
	(m_or_m    (+ (if min? -1 0) (if max? 1 0)))
	
	(ia-iexpr  (unless msg (funcall pvsexpr-to-strobj ia-expr precision ia-vars subs)))
	(names     (unless msg (append (mapcar #'car *ia-let-names*) (list name))))
	(exprs     (unless msg (append (mapcar #'cdr *ia-let-names*) (list ia-iexpr))))
	
	(namexprs  (merge-lists names exprs))
	(ia-dirvar (or dirvar (cond ((< m_or_m 0) "mindir_maxvar")
				    ((> m_or_m 0) "maxdir_maxvar")
				    (t "altdir_maxvar"))))
	(maxdepth  (if (null ia-vars) 0 maxdepth))
	(ia-eval   (format nil "~a(~a,~a,~a,~a)(~a,~a)"
			   bandb-function-name maxdepth accuracy ia-dirvar m_or_m name ia-box))
	(ia-lvars  (format nil "list2array(0)((:~{~a~^, ~}:))" ia-vars))
	(msg       (or msg (when (listp ia-iexpr) (car ia-iexpr)))))
    (if msg
	(printf msg)
      (spread
       (name-label* namexprs :hide? t)
       ((try-branch
	 (eval-expr ia-eval :safe? nil)
	 ((let ((output (args2 (extra-get-formula -1)))
		(depth  (extra-get-number-from-expr (get-expr-from-obj output 'depth)))
		(splits (get-expr-from-obj output 'splits))
		(ans    (get-expr-from-obj output 'ans)))
	    (if (and (name-expr? ans) (eq (id ans) 'None))
		(then (printf "Error evaluating the expression. ~%HINT: Check if all the operations in the expression are supported by the strategy.") (fail))
	      (let ((ans    (if (record-expr? ans) ans (args1 ans)))
		    (lbacc  (ratio2decimal (- (extra-get-number-from-expr 
					       (get-expr-from-obj ans 'lb_max))
					      (extra-get-number-from-expr 
					       (get-expr-from-obj ans 'mm 'lb)))
					   true precision))
		    (ubacc  (ratio2decimal (- (extra-get-number-from-expr 
					       (get-expr-from-obj ans 'mm 'ub))
					      (extra-get-number-from-expr 
					       (get-expr-from-obj ans 'ub_min)))
					   true precision))
		    (eqs    (extra-evalexprs))
		    (maxd   (and ia-vars (= depth maxdepth))))
		(with-fresh-labels 
		 (!iax)
		 (relabel label -1)
		 (lemma soundness-lemma-name)
		 (inst? -1)
		 (replaces label)
		 (beta -1)
		 (expand "sound?" -1)
		 (apply (repeat (expand "length" -1)))
		 (extra-evalexprs$ eqs !iax)
		 (branch
		  (split -1)
		  ((then
		    (flatten)
		    (relabel label (-2 -3 -4 -5))
		    (hide label)
		    (spread
		     (inst -1 ia-lvars)
		     ((branch
		       (invoke (case "%1 = %2") (! -1 1) ia-estr)
		       ((then 
			 (when verbose?
			   (printf "~%----")
			   (when maxd
			     (printf "Maximum depth has been reached."))
			   (printf "Lower bound accuracy <= ~a" lbacc) 
			   (printf "Upper bound accuracy <= ~a" ubacc)
			   (printf "Splits: ~a. Depth: ~a~%----~%" splits depth)
			   (printf "See hidden formulas labeled \"~a\" for more information"
				   label))
			 (replaces -1)
			 (decimalize -1 precision))
			(then (hide -1) (when equiv? (interval-eq__$ names 1 subs)))
			(then (hide -1) (reveal !iax) (replaces !iax :hide? nil) (vars-sharp__$))))
		      (if (null ia-vars)
			  (eval-formula)
			(then 
			 (reveal !iax)
			 (replaces !iax :hide? nil) 
			 (vars-in-box__$))))))
		   (eval-formula)))))))
	  (skip))
	 (skip))))))
"Computes lower and upper bounds of the minimum and maximum values of
EXPR using the algorithm called BANDB-FUNCTION-NAME. Its soundness must
be guaranteed by a lemma of name SOUNDNESS-LEMMA-NAME.

REQUIRED-THEORIES is used to indicate the theories needed to be imported
in order to use the strategy. It should be a list of the form
((<th_1> ... <th_n>) <error msg>) or (<th_1> ... <th_n>) where every
th_i is a theory name and <error msg> is a custom error message.
The name of the function to translate a pvs expression to a string
representation of a ObjType is the parameter PVSEXPR-TO-STROBJ.

PRECISION is the number of decimals in the output interval. PRECISION also
indicates an accuracy of 10^-PRECISION in every atomic computation. However,
this accuracy is not guaranteed in the final result. MAXDEPTH is a maximum
recursion depth for the branch and bound algorithm. For efficiency, the MIN?
and MAX? options can be used to restrict the precision of the computations
to either the lower or upper bound, respectively.

VARS is a list of the form (<v1> ... <vn>), where each <vi> is either a
variable name, e.g., \"x\", or a list consisting of a variable name and
an interval, e.g., (\"x\" \"[|-1/3,1/3|]\"). This list is used to specify
the variables in EXPR and to provide their ranges. If this list is not
provided, this information is extracted from the sequent.

SUBS is a list of substitutions for translating user-defined
real-valued functions into interval ones. Each substitution has the
form (<f> <F>), where <f> is the name of a real-valued function and
<F> is the name of its interval counterpart. It is assumed that <F>
satisfies the Inclusion and the Fundamental theorems of interval
arithmetic for <f>. Standard substitutions for basic arithmetic
operators, abs, sq, sqrt, trigonometric functions, exp, and ln are
already provided. This parameter can be used to change the precision
for a particular function, e.g., ((\"pi\" \"PI_n(4)\") (\"cos\"
(\"COS_n\" 1))(\"sin\" (\"SIN_n\" -1))) specifies the precision 4,
PRECISION+1, and PRECISION-1 for pi, cos, and sin, respectively.

DIRVAR is the name of a direction and variable selection method for
the branch an bound algorithm. Theory numerical_bandb includes some
pre-defined methods. If none is provided, a choice is made base on the
problem.

If VERBOSE? is set to t, the strategy prints information about number of
splits, depth, etc. 

LABEL is used to label formulas containing additional information computed
by the branch and bound algorithm. These formulas are hidden, but they can
be brought to the sequent using the proof command REVEAL.

If EQUIV? is set to nil, the strategy doesn't try to prove that the
deep embedding of the original expression is correct. The proof of
this fact is trivial from a logical point of view, but requires
unfolding of several definitions which is time consuming in PVS." "")

;; PRECiSA

(defun add-bb-ia-op (ops)
  (loop for new-elem in ops
	do (when (not (member new-elem *ia-extended*)) (setq *ia-extended* (cons new-elem *ia-extended*)))))

(add-bb-ia-op '(("ulp_sp" "ULP_SP")
		("aeboundsp_add""bbiasp_add.AEB_ADD")
		("aeboundsp_sub""bbiasp_sub.AEB_SUB")
		("aeboundsp_mul""bbiasp_mul.AEB_MUL")
		("aeboundsp_div""bbiasp_div.AEB_DIV")
		("aeboundsp_flr""bbiasp_flr.AEB_FLR")
		("aeboundsp_sqt""bbiasp_sqt.AEB_SQT")
		("aeboundsp_neg""bbiasp_neg.AEB_NEG")))

(add-bb-ia-op '(("ulp_dp" "ULP_DP")
		("aebounddp_add""bbiadp_add.AEB_ADD")
		("aebounddp_sub""bbiadp_sub.AEB_SUB")
		("aebounddp_mul""bbiadp_mul.AEB_MUL")
		("aebounddp_div""bbiadp_div.AEB_DIV")
		("aebounddp_flr""bbiadp_flr.AEB_FLR")
		("aebounddp_sqt""bbiadp_sqt.AEB_SQT")
		("aebounddp_neg""bbiadp_neg.AEB_NEG"))) 
