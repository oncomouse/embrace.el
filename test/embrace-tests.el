;;; embrace-tests.el --- ert tests for embrace on expreg  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with `make test' (vendors expreg 1.4.1 into test/externals).
;; Every unit test asserts the exact region text, so a change in expreg's
;; tagged output that breaks a semantic unit shows up here.

;;; Code:

(require 'ert)
(require 'embrace)
(require 'expreg)

(defmacro embrace-test-with (mode text &rest body)
  "In a temp buffer in MODE with TEXT, run BODY.
POINT is placed where | is in TEXT; the | itself is not inserted."
  (declare (indent 2))
  `(with-temp-buffer
     (funcall ,mode)
     (insert ,text)
     (goto-char (point-min))
     (re-search-forward "|")
     (delete-char -1)
     ,@body))

(defun embrace-test-region ()
  "The marked region as a string, or nil when nothing is marked."
  (cond
   ((region-active-p)
    (buffer-substring-no-properties (region-beginning) (region-end)))
   (mark-active
    (buffer-substring-no-properties (mark) (point)))
   (t nil)))

(defun embrace-test-region-bounds ()
  "The marked region as (BEG . END), or nil when nothing is marked."
  (when (or (region-active-p) mark-active)
    (cons (region-beginning) (region-end))))

;; ---------------------------------------------------------------------------
;; Unit engine: word / symbol
;; ---------------------------------------------------------------------------

(ert-deftest embrace-mark-word-marks-the-word-at-point ()
  (embrace-test-with 'emacs-lisp-mode "one t|wo three"
    (should (equal (progn (embrace-mark-word) (embrace-test-region)) "two"))))

(ert-deftest embrace-mark-word-stops-at-underscore ()
  (embrace-test-with 'emacs-lisp-mode "foo_b|ar baz"
    (should (equal (progn (embrace-mark-word) (embrace-test-region)) "bar"))))

(ert-deftest embrace-mark-symbol-includes-underscores ()
  (embrace-test-with 'emacs-lisp-mode "foo_b|ar baz"
    (should (equal (progn (embrace-mark-symbol) (embrace-test-region)) "foo_bar"))))

;; ---------------------------------------------------------------------------
;; Unit engine: pairs (lists)
;; ---------------------------------------------------------------------------

(ert-deftest embrace-mark-inside-pairs-trims-padding ()
  "The smaller (whitespace-trimmed) inside-list wins over the padded one."
  (embrace-test-with 'emacs-lisp-mode "(  alpha b|eta  )"
    (should (equal (progn (embrace-mark-inside-pairs) (embrace-test-region))
                   "alpha beta"))))

(ert-deftest embrace-mark-inside-pairs-picks-innermost ()
  (embrace-test-with 'emacs-lisp-mode "(aaa (inn|er))"
    (should (equal (progn (embrace-mark-inside-pairs) (embrace-test-region))
                   "inner"))))

(ert-deftest embrace-mark-outside-pairs-picks-innermost ()
  (embrace-test-with 'emacs-lisp-mode "(aaa (inn|er))"
    (should (equal (progn (embrace-mark-outside-pairs) (embrace-test-region))
                   "(inner)"))))

(ert-deftest embrace-mark-outside-pairs-includes-delimiters ()
  (embrace-test-with 'emacs-lisp-mode "(alpha b|eta)"
    (should (equal (progn (embrace-mark-outside-pairs) (embrace-test-region))
                   "(alpha beta)"))))

;; ---------------------------------------------------------------------------
;; Unit engine: quotes
;; ---------------------------------------------------------------------------

(ert-deftest embrace-mark-inside-quotes-excludes-quote-chars ()
  (embrace-test-with 'emacs-lisp-mode "\"hello w|orld\""
    (should (equal (progn (embrace-mark-inside-quotes) (embrace-test-region))
                   "hello world"))))

(ert-deftest embrace-mark-outside-quotes-includes-quote-chars ()
  (embrace-test-with 'emacs-lisp-mode "\"hello w|orld\""
    (should (equal (progn (embrace-mark-outside-quotes) (embrace-test-region))
                   "\"hello world\""))))

(ert-deftest embrace-mark-outside-quotes-handles-backquote-pair ()
  "expreg--string cannot see `...' pairs; embrace--quote-regions must."
  (embrace-test-with 'emacs-lisp-mode "x `foo b|ar' y"
    (setq-local embrace-quote-pairs '((?` . ?')))
    (should (equal (progn (embrace-mark-outside-quotes) (embrace-test-region))
                   "`foo bar'"))))

(ert-deftest embrace-mark-inside-quotes-handles-backquote-pair ()
  (embrace-test-with 'emacs-lisp-mode "x `foo b|ar' y"
    (setq-local embrace-quote-pairs '((?` . ?')))
    (should (equal (progn (embrace-mark-inside-quotes) (embrace-test-region))
                   "foo bar"))))

(ert-deftest embrace-quote-regions-skips-escaped-quote ()
  "An escaped quote does not terminate the quoted region."
  (embrace-test-with 'emacs-lisp-mode "x `it\\'s b|ar' y"
    (setq-local embrace-quote-pairs '((?` . ?')))
    (should (equal (progn (embrace-mark-outside-quotes) (embrace-test-region))
                   "`it\\'s bar'"))))

(ert-deftest embrace-emacs-lisp-mode-hook-registers-backquote-pair ()
  (embrace-test-with 'emacs-lisp-mode "x `foo b|ar' y"
    (embrace-emacs-lisp-mode-hook)
    (should (equal (progn (embrace-mark-outside-quotes) (embrace-test-region))
                   "`foo bar'"))))

;; ---------------------------------------------------------------------------
;; Unit engine: comment / paragraph / defun  (trailing newline must be trimmed)
;; ---------------------------------------------------------------------------

(ert-deftest embrace-mark-comment-trims-trailing-newline ()
  (embrace-test-with 'emacs-lisp-mode ";; comm|ent text\n"
    (should (equal (progn (embrace-mark-comment) (embrace-test-region))
                   ";; comment text"))))

(ert-deftest embrace-mark-comment-trailing-on-code-line ()
  (embrace-test-with 'emacs-lisp-mode "(foo) ;; trail|ing\n"
    (should (equal (progn (embrace-mark-comment) (embrace-test-region))
                   ";; trailing"))))

(ert-deftest embrace-mark-paragraph-trims-trailing-newline ()
  (embrace-test-with 'text-mode "para one.\n\npara t|wo here\n"
    (should (equal (progn (embrace-mark-paragraph) (embrace-test-region))
                   "para two here"))))

(ert-deftest embrace-mark-defun-with-expreg-paragraph-defun ()
  (embrace-test-with 'c-ts-mode "int main(void) {\n  return fo|o;\n}\n"
    (should (equal (progn (embrace-mark-defun) (embrace-test-region))
                   "int main(void) {\n  return foo;\n}"))))

(ert-deftest embrace-mark-defun-falls-back-to-builtin-in-elisp ()
  "`beginning-of-defun-function' is nil in emacs-lisp-mode, so expreg
produces no defun region; the adapter must fall back to the builtin."
  (embrace-test-with 'emacs-lisp-mode "(defun foo ()\n  (bar |baz))\n"
    (should-not beginning-of-defun-function)
    (should (equal (progn (embrace-mark-defun) (embrace-test-region))
                   "(defun foo ()\n  (bar baz))"))))

(ert-deftest embrace-mark-sentence-marks-sentence ()
  (embrace-test-with 'text-mode "first sent.\n\nsecond sent|ence.\n\nthird.\n"
    (should (equal (progn (embrace-mark-sentence) (embrace-test-region))
                   "second sentence."))))

;; ---------------------------------------------------------------------------
;; Unit engine: tree-sitter node
;; ---------------------------------------------------------------------------

(ert-deftest embrace-mark-ts-node-returns-treesit-tag ()
  (embrace-test-with 'c-ts-mode "int main(void) {\n  return fo|o;\n}\n"
    (should (eq (embrace-mark-ts-node) 'treesit--c))
    (should (equal (embrace-test-region) "foo"))))

(ert-deftest embrace-mark-unit-returns-nil-when-no-tag-matches ()
  (embrace-test-with 'emacs-lisp-mode "plain word| here"
    (should-not (embrace--mark-tagged '(expreg--string) '(string-inside)))))

;; ---------------------------------------------------------------------------
;; Legacy (er/mark-*) unit-name resolution
;; ---------------------------------------------------------------------------

(ert-deftest embrace-resolve-unit-passes-new-function-names ()
  (should (eq (embrace--resolve-unit 'embrace-mark-word)
                (symbol-function 'embrace-mark-word))))

(ert-deftest embrace-resolve-unit-passes-lambda ()
  (let ((fn (lambda () nil)))
    (should (eq (embrace--resolve-unit fn) fn))))

(ert-deftest embrace-resolve-unit-maps-legacy-expand-region-names ()
  (should (eq (embrace--resolve-unit 'er/mark-word)
                (symbol-function 'embrace-mark-word)))
  (should (eq (embrace--resolve-unit 'er/mark-inside-quotes)
                (symbol-function 'embrace-mark-inside-quotes)))
  (should (eq (embrace--resolve-unit 'er/mark-outside-pairs)
                (symbol-function 'embrace-mark-outside-pairs)))
)

(ert-deftest embrace-resolve-unit-provides-email-and-url-without-expand-region ()
  "The old defaults came from expand-region; they must work without it."
  (should (functionp (embrace--resolve-unit 'er/mark-email)))
  (embrace-test-with 'text-mode "mail foo@bar|.com now"
    (funcall (embrace--resolve-unit 'er/mark-email))
    (should (equal (embrace-test-region) "foo@bar.com"))))

(ert-deftest embrace-resolve-unit-returns-nil-for-unknown-name ()
  (should-not (embrace--resolve-unit 'er/mark-nonexistent-thing)))

(ert-deftest embrace-resolve-unit-prefers-a-real-expand-region-function ()
  "If the user still has expand-region loaded, its function wins."
  (cl-letf (((symbol-function 'er/mark-word) (lambda () (ignore))))
    (should (eq (embrace--resolve-unit 'er/mark-word)
                (symbol-function 'er/mark-word)))))

;; ---------------------------------------------------------------------------
;; Default semantic unit table
;; ---------------------------------------------------------------------------

(ert-deftest embrace-default-units-all-resolve ()
  (dolist (entry embrace-semantic-units-alist)
    ;; defaults must name embrace functions, not legacy expand-region names
    (should-not (assq (cdr entry) embrace--legacy-unit-aliases))
    (should (functionp (embrace--resolve-unit (cdr entry))))))

(ert-deftest embrace-default-units-include-comment-and-ts-node ()
  (should (assq ?c embrace-semantic-units-alist))
  (should (assq ?n embrace-semantic-units-alist)))

(ert-deftest embrace-default-unit-keys-unchanged ()
  "The keys users already press must not change."
  (let ((keys (mapcar #'car embrace-semantic-units-alist)))
    (dolist (k '(?w ?s ?d ?P ?p ?Q ?q ?. ?h))
      (should (memq k keys)))))

;; ---------------------------------------------------------------------------
;; Pair research (embrace-change / embrace-delete)
;; ---------------------------------------------------------------------------

(ert-deftest embrace-find-pair-from-outside-list ()
  (embrace-test-with 'emacs-lisp-mode "(alpha b|eta)"
    (let ((bounds (embrace--find-pair "(" ")")))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "(alpha beta)")))))

(ert-deftest embrace-find-pair-prefers-innermost ()
  (embrace-test-with 'emacs-lisp-mode "(outer (foo|bar))"
    (let ((bounds (embrace--find-pair "(" ")")))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "(foobar)")))))

(ert-deftest embrace-find-pair-tag-via-fallback ()
  (embrace-test-with 'emacs-lisp-mode "<div class=\"x\">he|llo</div>"
    (let ((bounds (embrace--find-pair "<[^>]*?>" "</[^>]*?>")))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "<div class=\"x\">hello</div>")))))

(ert-deftest embrace-find-pair-function-call-via-fallback ()
  (embrace-test-with 'emacs-lisp-mode "bar(\"fo|o\")"
    (let ((bounds (embrace--find-pair "\\(\\w\\|\\s_\\)+?(" ")")))
      (should (equal (buffer-substring-no-properties (car bounds) (cdr bounds))
                     "bar(\"foo\")")))))

(ert-deftest embrace-find-pair-returns-nil-when-absent ()
  (embrace-test-with 'emacs-lisp-mode "no pair he|re"
    (should-not (embrace--find-pair "(" ")"))))

(ert-deftest embrace-find-pair-leaves-expreg-state-untouched ()
  "The old implementation called expreg-expand and left stale state behind,
so the user's next C-= resumed embrace's search. Ours must not."
  (embrace-test-with 'emacs-lisp-mode "(alpha b|eta)"
    (should-not expreg--next-regions)
    (embrace--find-pair "(" ")")
    (should-not expreg--next-regions)
    (should-not expreg--prev-regions)))

(ert-deftest embrace-unit-marking-leaves-expreg-state-untouched ()
  (embrace-test-with 'emacs-lisp-mode "(alpha b|eta)"
    (embrace-mark-inside-pairs)
    (should-not expreg--next-regions)
    (should-not expreg--prev-regions)))

;; ---------------------------------------------------------------------------
;; Insert / delete round-trips (evil-embrace depends on these signatures)
;; ---------------------------------------------------------------------------

(ert-deftest embrace-insert-wraps-the-overlay ()
  (embrace-test-with 'emacs-lisp-mode "say hello| now"
    (goto-char (point-min))
    (search-forward "hello")
    (let ((ov (make-overlay (match-beginning 0) (match-end 0) nil nil t)))
      (embrace--insert ?\( ov)
      (should (equal (buffer-string) "say (hello) now")))))

(ert-deftest embrace-delete-removes-the-pair ()
  (embrace-test-with 'emacs-lisp-mode "say (he|llo) now"
    (should (equal (progn (embrace--delete ?\() (buffer-string))
                   "say hello now"))))

(ert-deftest embrace-change-swaps-one-pair-for-another ()
  (embrace-test-with 'emacs-lisp-mode "say (he|llo) now"
    (let ((ov (embrace--delete ?\( t)))
      (embrace--insert ?\[ ov)
      (should (equal (buffer-string) "say [hello] now")))))

(ert-deftest embrace-delete-backquote-pair-registered-by-elisp-hook ()
  (embrace-test-with 'emacs-lisp-mode "say `he|llo' now"
    (embrace-emacs-lisp-mode-hook)
    (should (equal (progn (embrace--delete ?`) (buffer-string))
                   "say hello now"))))

(ert-deftest embrace-delete-errors-when-pair-absent ()
  (embrace-test-with 'emacs-lisp-mode "no pair he|re at all"
    (should-error (embrace--delete ?\())))

(ert-deftest embrace-insert-auto-newline-adds-line-breaks ()
  (embrace-test-with 'emacs-lisp-mode "say hello| now"
    (embrace-add-pair ?x "«" "»" nil t)
    (goto-char (point-min))
    (search-forward "hello")
    (let ((ov (make-overlay (match-beginning 0) (match-end 0) nil nil t)))
      (embrace--insert ?x ov)
      (should (equal (buffer-string) "say «\nhello\n» now")))))

(ert-deftest embrace-unit-help-lists-the-new-unit-names ()
  (embrace-test-with 'emacs-lisp-mode "word| here"
    (let ((help (mapconcat #'identity
                          (mapcar (lambda (row) (mapconcat #'identity row ""))
                                  (embrace--units-alist-to-keys))
                          "\n")))
      (should (string-match-p "embrace-mark-word" help))
      (should (string-match-p "embrace-mark-ts-node" help))
      (should-not (string-match-p "er/mark-" help)))))

(ert-deftest embrace-pair-help-renders-every-default-pair ()
  (embrace-test-with 'emacs-lisp-mode "word| here"
    (let ((help (mapconcat #'identity
                          (mapcar (lambda (row) (mapconcat #'identity row ""))
                                  (mapcar #'embrace--pair-struct-to-keys
                                          (mapcar #'cdr embrace--pairs-list)))
                          "\n")))
      (should (string-match-p "function(" help))
      (should (string-match-p "<tag attr>" help)))))

;; ---------------------------------------------------------------------------
;; End-to-end command paths (help display off, read-char fed from a queue)
;; ---------------------------------------------------------------------------

(defmacro embrace-test-commands (mode text keys &rest body)
  "In MODE with TEXT, run BODY with READ-CHAR returning KEYS in order.
| marks point.  Help windows are suppressed."
  (declare (indent 3))
  `(embrace-test-with ,mode ,text
     (let ((embrace-show-help-p nil)
           (queue (list ,@keys)))
       (cl-letf (((symbol-function (quote read-char))
                  (lambda (&rest _)
                    (if queue (pop queue) (error "no more keys")))))
         ,@body))))

(ert-deftest embrace-add-asks-for-unit-then-pair ()
  (embrace-test-commands 'emacs-lisp-mode "say hello| now"
      (?w ?\()
    (call-interactively (quote embrace-add))
    (should (equal (buffer-string) "say (hello) now"))))

(ert-deftest embrace-change-swaps-the-named-pair ()
  (embrace-test-commands 'emacs-lisp-mode "say (he|llo) now"
      (?\( ?\[)
    (call-interactively (quote embrace-change))
    (should (equal (buffer-string) "say [hello] now"))))

(ert-deftest embrace-delete-removes-the-named-pair ()
  (embrace-test-commands 'emacs-lisp-mode "say (he|llo) now"
      (?\()
    (call-interactively (quote embrace-delete))
    (should (equal (buffer-string) "say hello now"))))

(ert-deftest embrace-commander-dispatches-add-change-delete ()
  (embrace-test-commands 'emacs-lisp-mode "one two| three"
      (?a ?w ?\{)
    (call-interactively (quote embrace-commander))
    (should (equal (buffer-string) "one {two} three"))))

(ert-deftest embrace-add-uses-existing-region-and-skips-the-unit ()
  "With a region already active the unit prompt must not be consumed."
  (embrace-test-commands 'emacs-lisp-mode "say |hello now"
      (?\()
    ;; batch starts with transient-mark-mode off, which makes `use-region-p'
    ;; useless; turn it on so this exercises the real code path.
    (let ((transient-mark-mode t))
      (goto-char (point-min))
      (search-forward "hello")
      (set-mark (match-beginning 0))
      (activate-mark)
      (call-interactively (quote embrace-add))
      (should (equal (buffer-string) "say (hello) now")))))

(provide 'embrace-tests)
;;; embrace-tests.el ends here
