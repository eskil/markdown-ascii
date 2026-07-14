;;; markdown-ascii.el --- Plain-text Markdown preview  -*- lexical-binding: t -*-
;;
;; Author: Eskil Olsen
;; Version: 1.0.2
;; Package-Requires: ((emacs "27.1"))
;; Keywords: markdown, text, preview
;; URL: https://github.com/eskil/markdown-ascii
;;
;;; Commentary:
;;
;; Text-mode Markdown preview for Emacs.  Renders Markdown as
;; formatted plain text with faces — no HTML, no browser.
;;
;; Usage:
;;   M-x markdown-ascii-preview      render current buffer in new window
;;   M-x markdown-ascii-live-mode    auto-refresh preview on save
;;
;;; Code:

(defgroup markdown-ascii nil "Text-mode Markdown preview." :group 'text)

(require 'cl-lib)

(defcustom markdown-ascii-width 72
  "Line width for horizontal rules."
  :type 'integer :group 'markdown-ascii)

(defcustom markdown-ascii-fill-column 80
  "Max line length for paragraph text. Set to 0 to disable wrapping."
  :type 'integer :group 'markdown-ascii)

;;; Faces
;; Clear cached specs so face changes take effect on reload.
(dolist (f '(markdown-ascii-h1 markdown-ascii-h2 markdown-ascii-h3 markdown-ascii-h4
             markdown-ascii-underline markdown-ascii-rule markdown-ascii-blockquote
             markdown-ascii-bold markdown-ascii-italic markdown-ascii-strikethrough
             markdown-ascii-checkbox-todo markdown-ascii-checkbox-done
             markdown-ascii-code markdown-ascii-inline-code markdown-ascii-line-number
             markdown-ascii-link-url markdown-ascii-table-border markdown-ascii-table-header
             markdown-ascii-diagram-border markdown-ascii-diagram-arrow
             markdown-ascii-diagram-participant markdown-ascii-diagram-title))
  (put f 'face-defface-spec nil))

(defface markdown-ascii-h1
  '((t :weight bold :foreground "#32CD32" :height 1.15))
  "H1 heading." :group 'markdown-ascii)

(defface markdown-ascii-h2
  '((t :weight bold :foreground "#32CD32" :height 1.05))
  "H2 heading." :group 'markdown-ascii)

(defface markdown-ascii-h3
  '((t :weight bold :foreground "#228B22"))
  "H3 heading." :group 'markdown-ascii)

(defface markdown-ascii-h4
  '((t :weight bold :foreground "#228B22"))
  "H4-H6 heading." :group 'markdown-ascii)

(defface markdown-ascii-underline
  '((t :foreground "gray55"))
  "Heading underline decoration." :group 'markdown-ascii)

(defface markdown-ascii-rule
  '((t :foreground "gray55"))
  "Horizontal rule." :group 'markdown-ascii)

(defface markdown-ascii-blockquote
  '((t :foreground "gray40" :slant italic))
  "Blockquote line." :group 'markdown-ascii)

(defface markdown-ascii-bold
  '((t :weight bold :foreground "white"))
  "Bold span." :group 'markdown-ascii)

(defface markdown-ascii-italic
  '((t :slant oblique :foreground "#DAA520"))
  "Italic span." :group 'markdown-ascii)

(defface markdown-ascii-strikethrough
  '((t :strike-through t :foreground "gray50"))
  "Strikethrough span." :group 'markdown-ascii)

(defface markdown-ascii-checkbox-todo
  '((t :foreground "white"))
  "Unchecked checkbox item." :group 'markdown-ascii)

(defface markdown-ascii-checkbox-done
  '((t :foreground "gray50"))
  "Checked checkbox item." :group 'markdown-ascii)

(defface markdown-ascii-code
  '((t :inherit fixed-pitch))
  "Code span / block." :group 'markdown-ascii)

(defface markdown-ascii-inline-code
  '((t :foreground "#5599FF"))
  "Inline `code` spans." :group 'markdown-ascii)

(defface markdown-ascii-line-number
  '((t :foreground "gray50"))
  "Line numbers in code blocks." :group 'markdown-ascii)

(defface markdown-ascii-link-url
  '((t :underline t :foreground "medium blue"))
  "Link URL." :group 'markdown-ascii)

(defface markdown-ascii-table-border
  '((t :foreground "gray50"))
  "Table border characters." :group 'markdown-ascii)

(defface markdown-ascii-table-header
  '((t :weight bold))
  "Table header cell text." :group 'markdown-ascii)

(defface markdown-ascii-diagram-border
  '((t :foreground "gray50"))
  "Box-drawing borders in diagram renderings." :group 'markdown-ascii)

(defface markdown-ascii-diagram-arrow
  '((t :foreground "#5599FF"))
  "Arrows and connectors in diagram renderings." :group 'markdown-ascii)

(defface markdown-ascii-diagram-participant
  '((t :weight bold :foreground "#DAA520"))
  "Participant/node labels in diagram renderings." :group 'markdown-ascii)

(defface markdown-ascii-diagram-title
  '((t :weight bold :foreground "#228B22"))
  "Title line in diagram renderings." :group 'markdown-ascii)

;;; Inline renderer

(defun markdown-ascii--propertize-inline (s)
  "Apply face properties to inline markup in S in a single left-to-right pass.
Handles ***bold+italic***, **bold**, *italic*, __bold__, _italic_, `code`, <url>.
Bold is matched before italic so ** is never misread as two *."
  (let ((result "")
        (start 0)
        ;; Alternation order matters: *** before ** before *
        (re (concat "\\*\\*\\*\\([^*\n]+\\)\\*\\*\\*"   ; 1: bold+italic ***
                    "\\|___\\([^_\n]+\\)___"             ; 2: bold+italic ___
                    "\\|\\*\\*\\([^*\n]+\\)\\*\\*"       ; 3: bold **
                    "\\|__\\([^_\n]+\\)__"               ; 4: bold __
                    "\\|\\*\\([^*\n]+\\)\\*"             ; 5: italic *
                    "\\|_\\([^_\n]+\\)_"                 ; 6: italic _
                    "\\|`\\([^`\n]+\\)`"                 ; 7: code
                    "\\|~~\\([^~\n]+\\)~~"               ; 8: strikethrough
                    "\\|<https?:[^>\n]+>")))              ; 9: link url
    (while (string-match re s start)
      (setq result (concat result (substring s start (match-beginning 0))))
      (cond
       ((match-string 1 s)  ; ***bold+italic***
        (setq result (concat result
                             (propertize (match-string 1 s)
                                         'face '(markdown-ascii-bold markdown-ascii-italic)))))
       ((match-string 2 s)  ; ___bold+italic___
        (setq result (concat result
                             (propertize (match-string 2 s)
                                         'face '(markdown-ascii-bold markdown-ascii-italic)))))
       ((match-string 3 s)  ; **bold**
        (setq result (concat result
                             (propertize (match-string 3 s) 'face 'markdown-ascii-bold))))
       ((match-string 4 s)  ; __bold__
        (setq result (concat result
                             (propertize (match-string 4 s) 'face 'markdown-ascii-bold))))
       ((match-string 5 s)  ; *italic*
        (setq result (concat result
                             (propertize (match-string 5 s) 'face 'markdown-ascii-italic))))
       ((match-string 6 s)  ; _italic_
        (setq result (concat result
                             (propertize (match-string 6 s) 'face 'markdown-ascii-italic))))
       ((match-string 7 s)  ; `code`
        (setq result (concat result
                             (propertize (match-string 7 s) 'face 'markdown-ascii-inline-code))))
       ((match-string 8 s)  ; ~~strikethrough~~
        (setq result (concat result
                             (propertize (match-string 8 s) 'face 'markdown-ascii-strikethrough))))
       (t                   ; <url>
        (setq result (concat result
                             (propertize (match-string 0 s) 'face 'markdown-ascii-link-url)))))
      (setq start (match-end 0)))
    (concat result (substring s start))))

(defun markdown-ascii--render-inline (s)
  "Convert inline markdown in S to plain text, then propertize."
  ;; Images: ![alt](url) → [image: alt]
  (setq s (replace-regexp-in-string
           "!\\[\\([^]]*\\)\\]([^)]*)" "[image: \\1]" s))
  ;; Links: [text](url) → text <url>
  (setq s (replace-regexp-in-string
           "\\[\\([^]]+\\)\\](\\([^)]+\\))" "\\1 <\\2>" s))
  ;; Reference links: [text][ref] → text
  (setq s (replace-regexp-in-string
           "\\[\\([^]]+\\)\\]\\s-*\\[[^]]*\\]" "\\1" s))
  (markdown-ascii--propertize-inline s))

;;; Syntax highlighting

(defvar markdown-ascii--lang-modes
  '(("elisp"      . emacs-lisp-mode)
    ("el"         . emacs-lisp-mode)
    ("lisp"       . lisp-mode)
    ("python"     . python-mode)
    ("py"         . python-mode)
    ("javascript" . js-mode)
    ("js"         . js-mode)
    ("typescript" . typescript-mode)
    ("ts"         . typescript-mode)
    ("tsx"        . typescript-mode)
    ("jsx"        . js-mode)
    ("ruby"       . ruby-mode)
    ("rb"         . ruby-mode)
    ("rust"       . rust-mode)
    ("rs"         . rust-mode)
    ("go"         . go-mode)
    ("c"          . c-mode)
    ("cpp"        . c++-mode)
    ("c++"        . c++-mode)
    ("java"       . java-mode)
    ("sh"         . sh-mode)
    ("bash"       . sh-mode)
    ("shell"      . sh-mode)
    ("zsh"        . sh-mode)
    ("css"        . css-mode)
    ("html"       . html-mode)
    ("xml"        . xml-mode)
    ("json"       . js-mode)
    ("yaml"       . yaml-mode)
    ("yml"        . yaml-mode)
    ("toml"       . conf-toml-mode)
    ("sql"        . sql-mode)
    ("r"          . r-mode)
    ("swift"      . swift-mode)
    ("kotlin"     . kotlin-mode)
    ("scala"      . scala-mode)
    ("haskell"    . haskell-mode)
    ("hs"         . haskell-mode)
    ("ocaml"      . tuareg-mode)
    ("ml"         . tuareg-mode)
    ("elixir"     . elixir-mode)
    ("ex"         . elixir-mode)
    ("exs"        . elixir-mode)
    ("clojure"    . clojure-mode)
    ("clj"        . clojure-mode))
  "Map from fenced-code language tag to Emacs major mode symbol.")

(defun markdown-ascii--highlight-code (code lang)
  "Return CODE syntax-highlighted for LANG as a propertized string.
Falls back to plain `markdown-ascii-code' face if the mode is unavailable."
  (let ((mode (and (stringp lang)
                   (not (string-empty-p lang))
                   (cdr (assoc lang markdown-ascii--lang-modes)))))
    (if (and mode (fboundp mode))
        (with-temp-buffer
          (insert code)
          (delay-mode-hooks (funcall mode))
          (when (fboundp 'font-lock-ensure)
            (font-lock-ensure))
          (buffer-string))
      (propertize code 'face 'markdown-ascii-code))))

(defun markdown-ascii--wrap-lines (s max-col)
  "Wrap propertized string S at MAX-COL word boundaries.
Uses a temp buffer so text properties (faces) are preserved.
Returns list of line strings. Skips wrapping when MAX-COL is 0."
  (if (or (<= max-col 0) (<= (string-width s) max-col))
      (list s)
    (with-temp-buffer
      (insert s)
      (let ((fill-column max-col))
        (fill-region (point-min) (point-max)))
      (split-string (buffer-string) "\n"))))

;;; Table support

(defun markdown-ascii--table-row-p (line)
  "Non-nil if LINE looks like a markdown table row."
  (string-match "^[ \t]*|" line))

(defun markdown-ascii--table-sep-p (line)
  "Non-nil if LINE is a markdown table separator row (|---|---|)."
  (string-match "^[ \t]*|[ \t]*:?-+:?[ \t]*\\(|[ \t]*:?-*:?[ \t]*\\)*|?[ \t]*$" line))

(defun markdown-ascii--parse-table-cells (line)
  "Parse markdown table LINE into list of trimmed cell strings."
  (let* ((s (string-trim line))
         (s (if (string-prefix-p "|" s) (substring s 1) s))
         (s (if (string-suffix-p "|" s) (substring s 0 (1- (length s))) s)))
    (mapcar #'string-trim (split-string s "|"))))

(defun markdown-ascii--table-col-widths (all-rows ncols fill)
  "Compute column widths for ALL-ROWS.
When the natural table width exceeds FILL, pins columns that fit within
their equal share of the budget, then distributes the remainder
proportionally among the wide columns. FILL=0 disables shrinking."
  (let* ((naturals (vconcat
                    (mapcar (lambda (i)
                              (apply #'max 1
                                     (mapcar (lambda (row)
                                               (string-width (or (nth i row) "")))
                                             all-rows)))
                            (number-sequence 0 (1- ncols)))))
         (overhead (+ 1 (* 3 ncols)))
         (total    (+ overhead (apply #'+ (append naturals nil)))))
    (if (or (<= fill 0) (<= total fill))
        (append naturals nil)
      (let* ((widths  (copy-sequence naturals))
             (budget  (max ncols (- fill overhead)))
             (fixed   (make-vector ncols nil))
             (n-free  ncols)
             (budget-left budget)
             changed)
        ;; Iteratively pin columns whose natural width fits within equal share.
        (while (progn
                 (setq changed nil)
                 (when (> n-free 0)
                   (let ((share (/ (float budget-left) n-free)))
                     (dotimes (i ncols)
                       (when (and (not (aref fixed i))
                                  (<= (aref widths i) share))
                         (aset fixed i t)
                         (setq budget-left (- budget-left (aref widths i))
                               n-free      (1- n-free)
                               changed     t)))))
                 changed))
        ;; Distribute remaining budget among wide columns proportionally.
        (when (> n-free 0)
          (let ((free-sum (let ((s 0))
                            (dotimes (i ncols s)
                              (unless (aref fixed i)
                                (setq s (+ s (aref widths i))))))))
            (dotimes (i ncols)
              (unless (aref fixed i)
                (aset widths i (max 1 (floor (* budget-left
                                                (/ (float (aref widths i))
                                                   (max 1.0 (float free-sum)))))))))))
        (append widths nil)))))

(defun markdown-ascii--wrap-cell-text (text width)
  "Word-wrap TEXT into a list of strings each at most WIDTH chars wide."
  (if (<= (string-width text) width)
      (list text)
    (let ((words (split-string text " +" t))
          (lines '())
          (cur   ""))
      (dolist (word words)
        (cond
         ((string-empty-p cur)
          (setq cur (if (<= (string-width word) width) word
                      (substring word 0 width))))
         ((<= (+ (string-width cur) 1 (string-width word)) width)
          (setq cur (concat cur " " word)))
         (t
          (push cur lines)
          (setq cur (if (<= (string-width word) width) word
                      (substring word 0 width))))))
      (unless (string-empty-p cur) (push cur lines))
      (or (nreverse lines) (list "")))))

(defun markdown-ascii--table-hline (widths left fill-ch mid right)
  "Build a propertized horizontal table rule from box-drawing characters."
  (propertize
   (concat left
           (mapconcat (lambda (w) (make-string (+ w 2) (aref fill-ch 0)))
                      widths mid)
           right)
   'face 'markdown-ascii-table-border))

(defun markdown-ascii--table-row-lines (cells col-widths face)
  "Render table CELLS into display lines, wrapping cell content if needed.
FACE is applied to cell text (use `markdown-ascii-table-header' for header rows)."
  (let* ((ncols  (length col-widths))
         (border (propertize "│" 'face 'markdown-ascii-table-border))
         (wrapped (let (r)
                    (dotimes (i ncols)
                      (push (markdown-ascii--wrap-cell-text
                             (string-trim
                              (markdown-ascii--render-inline (or (nth i cells) "")))
                             (nth i col-widths))
                            r))
                    (nreverse r)))
         (nlines (apply #'max 1 (mapcar #'length wrapped)))
         (out '()))
    (dotimes (li nlines)
      (let ((line border))
        (dotimes (i ncols)
          (let* ((w         (nth i col-widths))
                 (cell-text (or (nth li (nth i wrapped)) ""))
                 (content   (if face (propertize cell-text 'face face) cell-text))
                 (pad       (make-string (max 0 (- w (string-width cell-text))) ?\s)))
            (setq line (concat line " " content pad " " border))))
        (push line out)))
    (nreverse out)))

(defun markdown-ascii--render-table (raw-rows fill)
  "Render RAW-ROWS (markdown table line strings) as a Unicode box table.
Returns a list of propertized display lines. Header row (before |---|)
is shown in bold; columns shrink to fit FILL when needed."
  (let ((header '()) (body '()) (found-sep nil))
    (dolist (row raw-rows)
      (cond
       ((markdown-ascii--table-sep-p row) (setq found-sep t))
       (found-sep (push (markdown-ascii--parse-table-cells row) body))
       (t         (push (markdown-ascii--parse-table-cells row) header))))
    (setq header (nreverse header)
          body   (nreverse body))
    (unless found-sep (setq body header header nil))
    (let* ((all    (append header body))
           (ncols  (apply #'max 1 (mapcar #'length all)))
           (widths (markdown-ascii--table-col-widths all ncols fill))
           (out '()))
      (push (markdown-ascii--table-hline widths "┌" "─" "┬" "┐") out)
      (dolist (row header)
        (dolist (l (markdown-ascii--table-row-lines row widths 'markdown-ascii-table-header))
          (push l out)))
      (when header
        (push (markdown-ascii--table-hline widths "╞" "═" "╪" "╡") out))
      (dolist (row body)
        (dolist (l (markdown-ascii--table-row-lines row widths nil))
          (push l out)))
      (push (markdown-ascii--table-hline widths "└" "─" "┴" "┘") out)
      (nreverse out))))

(defun markdown-ascii--push-code-block (highlighted result)
  "Push HIGHLIGHTED code lines with line numbers onto RESULT list; return new list."
  (let* ((lines (split-string highlighted "\n"))
         (total (length lines))
         (width (length (number-to-string total)))
         (fmt (concat "%" (number-to-string width) "d")))
    (let ((n 0))
      (dolist (l lines)
        (setq n (1+ n))
        (push (concat "  "
                      (propertize (format fmt n) 'face 'markdown-ascii-line-number)
                      (propertize "│" 'face 'markdown-ascii-line-number)
                      "    " l)
              result))))
  result)

;;; Mermaid diagram rendering

(defun markdown-ascii--render-mermaid-fallback (body)
  "Render BODY as a framed raw-code box labelled 'mermaid'."
  (let* ((lines    (split-string body "\n"))
         (max-col  (max 10 (- markdown-ascii-fill-column 4)))
         (inner-w  (min max-col
                        (apply #'max 0 (mapcar #'string-width lines))))
         (b        'markdown-ascii-diagram-border)
         (top-fill (max 0 (- inner-w 8)))   ; 8 = len("mermaid ")
         (top  (concat "  "
                       (propertize
                        (concat "┌── mermaid " (make-string top-fill ?─) "┐")
                        'face b)))
         (bot  (concat "  "
                       (propertize
                        (concat "└" (make-string (+ inner-w 2) ?─) "┘")
                        'face b)))
         (out  (list top)))
    (dolist (l lines)
      (let* ((w   (string-width l))
             (pad (make-string (max 0 (- inner-w w)) ?\s))
             (trunc (if (> w inner-w) (substring l 0 inner-w) l)))
        (push (concat "  "
                      (propertize "│" 'face b)
                      " "
                      (propertize trunc 'face 'markdown-ascii-code)
                      pad
                      " "
                      (propertize "│" 'face b))
              out)))
    (push bot out)
    (nreverse out)))

(defun markdown-ascii--render-mermaid-pie (body)
  "Render a mermaid pie chart as a horizontal bar chart."
  (let ((lines   (split-string body "\n"))
        (title   nil)
        (entries '()))
    ;; Parse title and entries
    (dolist (l lines)
      (cond
       ((string-match "^pie\\s-+title\\s-+\\(.*\\)$" l)
        (setq title (string-trim (match-string 1 l))))
       ((string-match "^\\s-*title\\s-+\\(.*\\)$" l)
        (unless title (setq title (string-trim (match-string 1 l)))))
       ((string-match "^\\s-*\"\\([^\"]+\\)\"\\s-*:\\s-*\\([0-9.]+\\)" l)
        (push (cons (match-string 1 l)
                    (string-to-number (match-string 2 l)))
              entries))))
    (setq entries (nreverse entries))
    (if (null entries)
        (markdown-ascii--render-mermaid-fallback body)
      (let* ((total    (apply #'+ (mapcar #'cdr entries)))
             (max-lw   (apply #'max 1 (mapcar (lambda (e) (string-width (car e))) entries)))
             (bar-max  (max 4 (min 20 (- markdown-ascii-fill-column max-lw 10))))
             (sep      (propertize (make-string (+ max-lw bar-max 8) ?─)
                                   'face 'markdown-ascii-diagram-border))
             (out      '()))
        (when title
          (push (concat "  " (propertize title 'face 'markdown-ascii-diagram-title)) out))
        (push (concat "  " sep) out)
        (dolist (e entries)
          (let* ((label   (car e))
                 (val     (cdr e))
                 (pct     (if (> total 0) (* 100.0 (/ (float val) total)) 0.0))
                 (filled  (if (> total 0)
                              (max (if (> val 0) 1 0)
                                   (round (* (/ (float val) total) bar-max)))
                            0))
                 (lpad    (make-string (max 0 (- max-lw (string-width label))) ?\s))
                 (bar     (propertize (make-string filled ?█) 'face 'markdown-ascii-bold))
                 (pct-s   (format "%.0f%%" pct)))
            (push (concat "  " label lpad "  " bar "  " pct-s) out)))
        (nreverse out)))))

(defun markdown-ascii--mermaid-seq-build-row (centers total-w active-face active-l active-r)
  "Build a lifeline or arrow row string for sequence diagrams.
CENTERS is a list of column-center positions.  The span from ACTIVE-L to
ACTIVE-R (inclusive positions) gets ACTIVE-FACE; everything outside gets
`markdown-ascii-diagram-border' on bar chars and spaces elsewhere.
Returns a propertized string of length TOTAL-W."
  (let ((row (make-string total-w ?\s)))
    (dolist (c centers) (aset row c ?│))
    row))

(defun markdown-ascii--render-mermaid-sequence (body)
  "Render a mermaid sequenceDiagram as participant columns with arrows."
  (let ((lines       (split-string body "\n"))
        (part-order  '())   ; list of id strings in encounter order
        (part-names  (make-hash-table :test 'equal))  ; id -> display name
        (messages    '()))
    ;; Pass 1: collect participants and messages
    (dolist (l lines)
      (let ((tl (string-trim l)))
        (cond
         ;; explicit participant declaration
         ((string-match "^\\s-*participant\\s-+\\(\\S-+\\)\\(?:\\s-+as\\s-+\\(.*\\)\\)?$" tl)
          (let* ((id   (match-string 1 tl))
                 (raw2 (match-string 2 tl))
                 (disp (if raw2 (string-trim raw2) id)))
            (unless (member id part-order)
              (push id part-order)
              (puthash id disp part-names))))
         ;; message line: A->>B: text  or  A-->>B: text  etc.
         ((string-match
           "^\\s-*\\([A-Za-z0-9_]+\\)\\s-*\\(--?>>\\|--?x\\|--?)\\|->>\\|->\\)\\s-*\\([A-Za-z0-9_]+\\)\\s-*:\\s-*\\(.*\\)$"
           tl)
          (let* ((from (match-string 1 tl))
                 (arr  (match-string 2 tl))
                 (to   (match-string 3 tl))
                 (lbl  (let ((s (match-string 4 tl))) (if s (string-trim s) ""))))
            ;; register unseen participants
            (dolist (id (list from to))
              (unless (member id part-order)
                (push id part-order)
                (puthash id id part-names)))
            (push (list from to arr lbl) messages))))))
    (setq part-order (nreverse part-order)
          messages   (nreverse messages))
    (if (null part-order)
        (markdown-ascii--render-mermaid-fallback body)
      ;; Layout
      (let* ((names    (mapcar (lambda (id) (gethash id part-names id)) part-order))
             (col-ws   (mapcar (lambda (n) (max (string-width n) 10)) names))
             (gap      4)
             ;; centers: list of absolute char positions
             (centers  (let ((pos 0) (cs '()))
                         (dolist (w col-ws)
                           (push (+ pos (/ w 2)) cs)
                           (setq pos (+ pos w gap)))
                         (nreverse cs)))
             (total-w  (+ (apply #'+ col-ws) (* gap (1- (length col-ws)))))
             (out      '()))
        ;; Header row: participant names
        (let ((hdr (make-string total-w ?\s)))
          (cl-mapcar
           (lambda (name center)
             (let* ((nw    (string-width name))
                    (start (max 0 (- center (/ nw 2)))))
               (dotimes (i (min nw (- total-w start)))
                 (aset hdr (+ start i) (aref name i)))))
           names centers)
          (push (concat "  " (propertize hdr 'face 'markdown-ascii-diagram-participant)) out))
        ;; Helper: emit a lifeline row
        (let ((emit-bar
               (lambda ()
                 (let ((row (make-string total-w ?\s)))
                   (dolist (c centers) (aset row c ?│))
                   (push (concat "  "
                                 (propertize row 'face 'markdown-ascii-diagram-border))
                         out)))))
          (funcall emit-bar)
          ;; Messages
          (dolist (msg messages)
            (let* ((from-id  (nth 0 msg))
                   (to-id    (nth 1 msg))
                   (arr-type (nth 2 msg))
                   (lbl      (nth 3 msg))
                   (fi       (cl-position from-id part-order :test #'equal))
                   (ti       (cl-position to-id   part-order :test #'equal))
                   (fc       (nth fi centers))
                   (tc       (nth ti centers))
                   (dashed   (string-match "^--" arr-type))
                   (arrow-ch (if (string-match "x$" arr-type) ?✕
                               (if (string-match ")$" arr-type) ?○ ?▶)))
                   (dash-ch  (if dashed ?╌ ?─)))
              (if (equal from-id to-id)
                  ;; Self-arrow: emit as note
                  (let ((note (make-string total-w ?\s)))
                    (dolist (c centers) (aset note c ?│))
                    (let* ((ins   (concat " ↩ " lbl))
                           (start (min (+ fc 1) (- total-w (string-width ins)))))
                      (dotimes (i (min (string-width ins) (- total-w start)))
                        (aset note (+ start i) (aref ins i))))
                    (push (concat "  "
                                  (propertize note 'face 'markdown-ascii-diagram-arrow))
                          out))
                ;; Regular arrow
                (let* ((left-c  (min fc tc))
                       (right-c (max fc tc))
                       (row     (make-string total-w ?\s)))
                  ;; Bars at non-involved columns
                  (dolist (ci (cl-mapcar #'cons part-order centers))
                    (let ((c (cdr ci)))
                      (unless (or (= c fc) (= c tc))
                        (aset row c ?│))))
                  ;; Arrow span
                  (let ((span-l (1+ left-c))
                        (span-r (1- right-c)))
                    (when (<= span-l span-r)
                      (cl-loop for p from span-l to span-r
                               do (aset row p dash-ch)))
                    ;; Arrowhead and tail bars
                    (if (> tc fc)
                        (progn (aset row fc ?│) (aset row tc arrow-ch))
                      (aset row tc ?│)
                      (aset row fc (if (= arrow-ch ?▶) ?◀ arrow-ch))))
                  ;; Overlay label centered in span
                  (let* ((lw    (string-width lbl))
                         (mid   (/ (+ left-c right-c) 2))
                         (ls    (max (1+ left-c) (- mid (/ lw 2))))
                         (avail (- right-c ls)))
                    (when (> avail 0)
                      (dotimes (i (min lw avail))
                        (aset row (+ ls i) (aref lbl i)))))
                  ;; Build propertized string in three segments
                  (push (concat "  "
                                (propertize (substring row 0 (1+ left-c))
                                            'face 'markdown-ascii-diagram-border)
                                (propertize (substring row (1+ left-c) right-c)
                                            'face 'markdown-ascii-diagram-arrow)
                                (propertize (substring row right-c)
                                            'face 'markdown-ascii-diagram-border))
                        out))))
            (funcall emit-bar)))
        (nreverse out)))))

(defun markdown-ascii--mermaid-parse-node (token)
  "Parse a mermaid node token like 'A[label]' or 'B{label}'.
Returns (id label shape) where shape is one of: box rounded diamond circle."
  (cond
   ((string-match "^\\([A-Za-z0-9_]+\\)\\[\\[\\(.*\\)\\]\\]$" token)
    (list (match-string 1 token) (match-string 2 token) 'box))
   ((string-match "^\\([A-Za-z0-9_]+\\)\\[\\(.*\\)\\]$" token)
    (list (match-string 1 token) (match-string 2 token) 'box))
   ((string-match "^\\([A-Za-z0-9_]+\\)((\\(.*\\)))$" token)
    (list (match-string 1 token) (match-string 2 token) 'circle))
   ((string-match "^\\([A-Za-z0-9_]+\\)(\\(.*\\))$" token)
    (list (match-string 1 token) (match-string 2 token) 'rounded))
   ((string-match "^\\([A-Za-z0-9_]+\\){\\(.*\\)}$" token)
    (list (match-string 1 token) (match-string 2 token) 'diamond))
   ((string-match "^\\([A-Za-z0-9_]+\\)$" token)
    (list (match-string 1 token) (match-string 1 token) 'box))
   (t (list token token 'box))))

(defun markdown-ascii--render-mermaid-flowchart (body)
  "Render a mermaid flowchart/graph with a linear layout.
Branches fall back to the framed box renderer."
  (let ((lines  (split-string body "\n"))
        (dir    "LR")
        (nodes  (make-hash-table :test 'equal))  ; id -> (label shape)
        (out-nb (make-hash-table :test 'equal))  ; id -> out-neighbor id
        (in-nb  (make-hash-table :test 'equal))  ; id -> in-neighbor id
        (all-ids '())
        (linear t))
    ;; Parse
    (let ((tail lines))
      (while (and tail linear)
        (let* ((l  (car tail))
               (tl (string-trim l)))
          (cond
           ((string-match "^\\(?:flowchart\\|graph\\)\\s-+\\([A-Z]+\\)" tl)
            (setq dir (match-string 1 tl)))
           ;; Edge line: split on --> --- ==>
           ((string-match "\\(-->\\|---\\|==>\\)" tl)
            (let* ((edge-re  "\\s-*\\(-->\\|---\\|==>\\)\\(?:|[^|]*|\\)?\\s-*")
                   (parts    (split-string tl edge-re t "\\s-+"))
                   (edge-types (let (et)
                                 (let ((s tl) (start 0))
                                   (while (string-match "-->\\|---\\|==>" s start)
                                     (push (match-string 0 s) et)
                                     (setq start (match-end 0))))
                                 (nreverse et))))
              (when (>= (length parts) 2)
                (let ((prev-id nil))
                  (dotimes (i (length parts))
                    (let* ((tok  (string-trim (nth i parts)))
                           (info (markdown-ascii--mermaid-parse-node tok))
                           (id   (car info)))
                      (unless (gethash id nodes)
                        (push id all-ids)
                        (puthash id (cdr info) nodes))
                      (when prev-id
                        (let ((etype (or (nth (1- i) edge-types) "-->")))
                          ;; Check for branching
                          (when (gethash prev-id out-nb) (setq linear nil))
                          (when (gethash id in-nb)       (setq linear nil))
                          (puthash prev-id (list id etype) out-nb)
                          (puthash id prev-id in-nb)))
                      (setq prev-id id))))))))
        (setq tail (cdr tail)))))
    (setq all-ids (nreverse all-ids))
    (if (or (not linear) (null all-ids) (= (hash-table-count out-nb) 0))
        (markdown-ascii--render-mermaid-fallback body)
      ;; Walk chain from root (node with no in-neighbor)
      (let* ((root (or (cl-find-if (lambda (id) (not (gethash id in-nb))) all-ids)
                       (car all-ids)))
             (chain '()))
        (let ((cur root))
          (while cur
            (let ((info (gethash cur nodes)))
              (push (list cur
                          (or (car info) cur)
                          (or (cadr info) 'box)
                          (car (gethash cur out-nb))
                          (cadr (gethash cur out-nb)))
                    chain)
              (setq cur (car (gethash cur out-nb))))))
        (setq chain (nreverse chain))
        ;; Build ASCII for LR vs TD
        (let ((vertical (member dir '("TD" "BT"))))
          (if vertical
              ;; ── vertical layout ──────────────────────────────────────
              (let ((out '()))
                (dolist (node chain)
                  (let* ((lbl     (nth 1 node))
                         (shape   (nth 2 node))
                         (has-next (nth 3 node))
                         (w       (string-width lbl))
                         (etype   (nth 4 node)))
                    (cond
                     ((eq shape 'diamond)
                      (push (concat "  "
                                    (propertize (concat "◇ " lbl " ◇")
                                                'face 'markdown-ascii-diagram-participant))
                            out))
                     ((eq shape 'circle)
                      (push (concat "  "
                                    (propertize (concat "○ " lbl " ○")
                                                'face 'markdown-ascii-diagram-participant))
                            out))
                     (t
                      (let* ((inner (+ w 2))
                             (top   (concat "┌" (make-string inner ?─) "┐"))
                             (mid   (concat "│ " lbl " │"))
                             (bot   (concat "└" (make-string inner ?─) "┘")))
                        (push (concat "  " (propertize top 'face 'markdown-ascii-diagram-border)) out)
                        (push (concat "  "
                                      (propertize "│" 'face 'markdown-ascii-diagram-border)
                                      " "
                                      (propertize lbl 'face 'markdown-ascii-diagram-participant)
                                      " "
                                      (propertize "│" 'face 'markdown-ascii-diagram-border))
                              out)
                        (push (concat "  " (propertize bot 'face 'markdown-ascii-diagram-border)) out))))
                    (when has-next
                      (let* ((conn-ch (if (string= etype "==>") ?═ ?─))
                             (arr     (if (string= etype "===") " " " ▼ ")))
                        (push (concat "  "
                                      (propertize (concat "  " (make-string 1 conn-ch)) 'face 'markdown-ascii-diagram-arrow))
                              out)
                        (push (concat "  "
                                      (propertize "  ▼" 'face 'markdown-ascii-diagram-arrow))
                              out)))))
                (nreverse out))
            ;; ── horizontal layout (LR default) ────────────────────────
            (let ((top-parts '())
                  (mid-parts '())
                  (bot-parts '()))
              (dolist (node chain)
                (let* ((lbl    (nth 1 node))
                       (shape  (nth 2 node))
                       (has-next (nth 3 node))
                       (etype  (nth 4 node))
                       (w      (string-width lbl)))
                  (cond
                   ((eq shape 'diamond)
                    (push (make-string (+ w 4) ?\s) top-parts)
                    (push (propertize (concat "◇ " lbl " ◇") 'face 'markdown-ascii-diagram-participant) mid-parts)
                    (push (make-string (+ w 4) ?\s) bot-parts))
                   ((eq shape 'circle)
                    (push (make-string (+ w 4) ?\s) top-parts)
                    (push (propertize (concat "○ " lbl " ○") 'face 'markdown-ascii-diagram-participant) mid-parts)
                    (push (make-string (+ w 4) ?\s) bot-parts))
                   (t
                    (let ((inner (+ w 2)))
                      (push (propertize (concat "┌" (make-string inner ?─) "┐") 'face 'markdown-ascii-diagram-border) top-parts)
                      (push (concat (propertize "│" 'face 'markdown-ascii-diagram-border)
                                    " "
                                    (propertize lbl 'face 'markdown-ascii-diagram-participant)
                                    " "
                                    (propertize "│" 'face 'markdown-ascii-diagram-border))
                            mid-parts)
                      (push (propertize (concat "└" (make-string inner ?─) "┘") 'face 'markdown-ascii-diagram-border) bot-parts))))
                  (when has-next
                    (let ((conn (cond ((string= etype "==>")
                                      (propertize " ══▶ " 'face 'markdown-ascii-diagram-arrow))
                                     ((string= etype "---")
                                      (propertize " ─── " 'face 'markdown-ascii-diagram-arrow))
                                     (t
                                      (propertize " ──▶ " 'face 'markdown-ascii-diagram-arrow)))))
                      (push "     " top-parts)
                      (push conn   mid-parts)
                      (push "     " bot-parts)))))
              ;; Check total width against fill-column
              (let ((total-w (apply #'+ (mapcar #'string-width
                                                (append top-parts mid-parts bot-parts)))))
                (if (> (/ total-w 3) markdown-ascii-fill-column)
                    (markdown-ascii--render-mermaid-fallback body)
                  (list (concat "  " (apply #'concat (nreverse top-parts)))
                        (concat "  " (apply #'concat (nreverse mid-parts)))
                        (concat "  " (apply #'concat (nreverse bot-parts)))))))))))))


(defun markdown-ascii--render-mermaid (body)
  "Render BODY (a mermaid diagram string) to a list of propertized display lines."
  (let* ((trimmed (string-trim body))
         (keyword (and (not (string-empty-p trimmed))
                       (car (split-string trimmed nil t)))))
    (cond
     ((string-empty-p trimmed)
      (list (propertize "  [empty mermaid diagram]" 'face 'markdown-ascii-code)))
     ((string-match "^sequenceDiagram" (or keyword ""))
      (markdown-ascii--render-mermaid-sequence trimmed))
     ((string-match "^pie" (or keyword ""))
      (markdown-ascii--render-mermaid-pie trimmed))
     ((string-match "^\\(flowchart\\|graph\\)" (or keyword ""))
      (markdown-ascii--render-mermaid-flowchart trimmed))
     (t
      (markdown-ascii--render-mermaid-fallback trimmed)))))

;;; Block renderer

(defun markdown-ascii--ul (text ch)
  "Make underline string matching width of TEXT using char CH."
  (make-string (string-width text) ch))

(defun markdown-ascii--hr ()
  "Render a horizontal rule."
  (propertize (make-string markdown-ascii-width ?─) 'face 'markdown-ascii-rule))

(defun markdown-ascii--heading (raw-text level)
  "Render heading RAW-TEXT at LEVEL, return list of propertized lines.
H1: text + two === lines.  H2: text + one === line.
H3: text + --- line.       H4+: text + ... line."
  (let* ((text (markdown-ascii--render-inline raw-text))
         (face (cond ((= level 1) 'markdown-ascii-h1)
                     ((= level 2) 'markdown-ascii-h2)
                     ((= level 3) 'markdown-ascii-h3)
                     (t           'markdown-ascii-h4)))
         (ul-ch (cond ((= level 1)  ?≡)
                      ((= level 2)  ?=)
                      ((= level 3)  ?-)
                      (t            ?.)))
         (ul (propertize (markdown-ascii--ul raw-text ul-ch) 'face 'markdown-ascii-underline))
         (ptext (propertize text 'face face)))
    (list ptext ul)))

(defun markdown-ascii--list-bullet (depth)
  "Return bullet string for list DEPTH."
  (nth (min depth 3) '("•" "◦" "▸" "▹")))

(defun markdown-ascii--strip-indent (line n)
  "Remove up to N leading whitespace characters from LINE."
  (if (string-match (concat "^[ \t]\\{0," (number-to-string n) "\\}") line)
      (substring line (match-end 0))
    line))

(defun markdown-ascii--flush-para (para-acc result fill)
  "Join PARA-ACC lines (LIFO order) with space, render inline, wrap, push to RESULT.
Returns updated RESULT."
  (when para-acc
    (let* ((joined (string-join (reverse para-acc) " "))
           (rendered (markdown-ascii--render-inline joined)))
      (dolist (l (markdown-ascii--wrap-lines rendered fill))
        (push l result))))
  result)

(defun markdown-ascii--render (text)
  "Render markdown TEXT string to a propertized plain-text string."
  (let ((lines (split-string text "\n"))
        (result '())
        (in-code nil)
        (code-fence "")
        (code-lang "")
        (code-indent 0)
        (code-acc '())
        (in-table nil)
        (table-rows '())
        (para-acc '())
        (prev-blank t))
    (dolist (raw lines)
      ;; ── flush table when leaving table context ────────────────────
      (when (and in-table (not in-code) (not (markdown-ascii--table-row-p raw)))
        (unless prev-blank (push "" result))
        (dolist (l (markdown-ascii--render-table (nreverse table-rows) markdown-ascii-fill-column))
          (push l result))
        (push "" result)
        (setq in-table nil table-rows '() prev-blank t))
      (cond
       ;; ── inside fenced code block ──────────────────────────────────
       (in-code
        (if (string-match (concat "^[ \t]\\{0," (number-to-string code-indent) "\\}"
                                   (regexp-quote code-fence) "`*\\s-*$") raw)
            (progn
              (setq in-code nil)
              (unless (or (null result) (string-empty-p (car result)))
                (push "" result))
              (let ((body (string-join (nreverse code-acc) "\n")))
                (if (equal code-lang "mermaid")
                    (dolist (l (markdown-ascii--render-mermaid body))
                      (push l result))
                  (setq result (markdown-ascii--push-code-block
                                (markdown-ascii--highlight-code body code-lang)
                                result))))
              (push "" result)
              (setq code-acc '()))
          (push (markdown-ascii--strip-indent raw code-indent) code-acc)))

       ;; ── fenced code block start (optionally indented, e.g. in a list) ──
       ((string-match "^\\([ \t]*\\)\\(```+\\|~~~+\\)\\s-*\\([a-zA-Z0-9+-]*\\)" raw)
        (let ((indent (or (match-string 1 raw) ""))
              (fence (or (match-string 2 raw) ""))
              (lang (downcase (or (match-string 3 raw) ""))))
          (when para-acc
            (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                  para-acc '()
                  prev-blank nil))
          (setq in-code t
                code-fence fence
                code-lang lang
                code-indent (length indent)
                code-acc '())))

       ;; ── ATX heading  # …  ─────────────────────────────────────────
       ((string-match "^\\(#\\{1,6\\}\\)[ \t]+\\(.*?\\)[ \t#]*$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
        (let* ((level (length (match-string 1 raw)))
               (htext (string-trim (match-string 2 raw)))
               (hlines (markdown-ascii--heading htext level)))
          (unless prev-blank (push "" result))
          (dolist (l hlines) (push l result))
          (push "" result)
          (setq prev-blank t)))

       ;; ── setext H1  (===) ──────────────────────────────────────────
       ((and (string-match "^=\\{2,\\}[ \t]*$" raw) para-acc)
        (let* ((heading-raw (car para-acc))
               (rest        (cdr para-acc)))
          (when rest
            (setq result (markdown-ascii--flush-para rest result markdown-ascii-fill-column)
                  prev-blank nil))
          (setq para-acc '())
          (unless prev-blank (push "" result))
          (dolist (l (markdown-ascii--heading heading-raw 1)) (push l result))
          (push "" result)
          (setq prev-blank t)))

       ;; ── setext H2  (---) ──────────────────────────────────────────
       ((and (string-match "^-\\{2,\\}[ \t]*$" raw) para-acc)
        (let* ((heading-raw (car para-acc))
               (rest        (cdr para-acc)))
          (when rest
            (setq result (markdown-ascii--flush-para rest result markdown-ascii-fill-column)
                  prev-blank nil))
          (setq para-acc '())
          (unless prev-blank (push "" result))
          (dolist (l (markdown-ascii--heading heading-raw 2)) (push l result))
          (push "" result)
          (setq prev-blank t)))

       ;; ── horizontal rule  --- / *** / ___ ─────────────────────────
       ((string-match "^\\([-*_][ \t]*\\)\\{3,\\}[ \t]*$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
        (unless prev-blank (push "" result))
        (push (markdown-ascii--hr) result)
        (push "" result)
        (setq prev-blank t))

       ;; ── blockquote  > … ───────────────────────────────────────────
       ((string-match "^>[ \t]?\\(.*\\)$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
        (push (propertize
               (concat "  │ " (markdown-ascii--render-inline (match-string 1 raw)))
               'face 'markdown-ascii-blockquote)
              result)
        (setq prev-blank nil))

       ;; ── unordered list  - / * / + ─────────────────────────────────
       ((string-match "^\\([ \t]*\\)[-*+][ \t]+\\(.*\\)$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
          (let* ((indent  (or (match-string 1 raw) ""))
                 (content (or (match-string 2 raw) ""))
                 (depth   (/ (length indent) 2))
               (pad     (make-string (* depth 2) ?\s)))
          (cond
           ((string-match "^\\[ \\][ \t]\\(.*\\)$" content)
            (push (concat "  " pad
                          (propertize "☐" 'face 'markdown-ascii-checkbox-todo)
                          " "
                          (markdown-ascii--render-inline (match-string 1 content)))
                  result))
           ((string-match "^\\[[xX]\\][ \t]\\(.*\\)$" content)
            (push (concat "  " pad
                          (propertize "☑" 'face 'markdown-ascii-checkbox-done)
                          " "
                          (propertize (markdown-ascii--render-inline (match-string 1 content))
                                      'face 'markdown-ascii-checkbox-done))
                  result))
           (t
            (push (concat "  " pad (markdown-ascii--list-bullet depth) " "
                          (markdown-ascii--render-inline content))
                  result)))
          (setq prev-blank nil)))

       ;; ── ordered list  1. / 1) ─────────────────────────────────────
       ((string-match "^\\([ \t]*\\)\\([0-9]+\\)[.)]\s+\\(.*\\)$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
          (let* ((indent (or (match-string 1 raw) ""))
                 (num (or (match-string 2 raw) ""))
                 (item-text (or (match-string 3 raw) ""))
                 (depth (/ (length indent) 3))
                 (text (markdown-ascii--render-inline item-text))
               (pad (make-string (* depth 3) ?\s)))
          (push (concat "  " pad num ". " text) result)
          (setq prev-blank nil)))

       ;; ── indented code (4 spaces or tab) ───────────────────────────
       ((string-match "^\\(?:    \\|\t\\)\\(.*\\)$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
        (push (propertize (concat "    " (match-string 1 raw)) 'face 'markdown-ascii-code)
              result)
        (setq prev-blank nil))

       ;; ── blank line ────────────────────────────────────────────────
       ((string-match "^[ \t]*$" raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()))
        (unless prev-blank (push "" result))
        (setq prev-blank t))

       ;; ── table row  | … | ─────────────────────────────────────────
       ((markdown-ascii--table-row-p raw)
        (when para-acc
          (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)
                para-acc '()
                prev-blank nil))
        (setq in-table t)
        (push raw table-rows))

       ;; ── paragraph text ────────────────────────────────────────────
       (t
        (push raw para-acc)
        (setq prev-blank nil))))

    ;; Flush remaining paragraph
    (when para-acc
      (setq result (markdown-ascii--flush-para para-acc result markdown-ascii-fill-column)))

    ;; Flush any pending table
    (when in-table
      (unless prev-blank (push "" result))
      (dolist (l (markdown-ascii--render-table (nreverse table-rows) markdown-ascii-fill-column))
        (push l result)))

    ;; Flush any unclosed code block
    (when in-code
      (let ((body (string-join (nreverse code-acc) "\n")))
        (if (equal code-lang "mermaid")
            (dolist (l (markdown-ascii--render-mermaid body))
              (push l result))
          (setq result (markdown-ascii--push-code-block
                        (markdown-ascii--highlight-code body code-lang)
                        result)))))

    (string-join (nreverse result) "\n")))

;;; Preview mode

(defvar markdown-ascii-preview-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "q" #'quit-window)
    (define-key map "g" #'markdown-ascii-preview-refresh)
    map))

(define-derived-mode markdown-ascii-preview-mode special-mode "TextMD"
  "Read-only buffer showing plain-text Markdown preview.
\\{markdown-ascii-preview-mode-map}"
  (setq buffer-read-only t
        truncate-lines nil))

;;;###autoload
(defun markdown-ascii-preview ()
  "Render current buffer's Markdown as a plain-text preview.
If the preview window is already visible, scroll position is preserved."
  (interactive)
  (let* ((src-buf  (current-buffer))
         (src-name (buffer-name src-buf))
         (text     (buffer-substring-no-properties (point-min) (point-max)))
         (rendered (markdown-ascii--render text))
         (buf-name (format "*TextMD: %s*" src-name))
         (preview-buf (get-buffer-create buf-name))
         (preview-win (get-buffer-window preview-buf t))
         (saved-point (when preview-win (window-point preview-win)))
         (saved-start (when preview-win (window-start preview-win))))
    (with-current-buffer preview-buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert rendered)
        (unless (eq major-mode 'markdown-ascii-preview-mode)
          (markdown-ascii-preview-mode))
        (setq-local markdown-ascii--source-buffer src-buf)))
    (if preview-win
        (progn
          (set-window-point preview-win
                            (min saved-point (with-current-buffer preview-buf (point-max))))
          (set-window-start preview-win
                            (min saved-start (with-current-buffer preview-buf (point-max))) t))
      (with-current-buffer preview-buf (goto-char (point-min)))
      (display-buffer preview-buf))))

(defun markdown-ascii-preview-refresh ()
  "Re-render preview from its source buffer."
  (interactive)
  (let ((src (and (boundp 'markdown-ascii--source-buffer) markdown-ascii--source-buffer)))
    (if (buffer-live-p src)
        (with-current-buffer src (markdown-ascii-preview))
      (message "markdown-ascii: source buffer gone"))))

;;; Live preview

(defvar-local markdown-ascii--live-timer nil
  "Idle timer for live preview updates in this buffer.")

(defun markdown-ascii--live-schedule (&rest _)
  "Schedule a preview refresh after a short idle period."
  (when (timerp markdown-ascii--live-timer)
    (cancel-timer markdown-ascii--live-timer))
  (setq markdown-ascii--live-timer
        (run-with-idle-timer 0.5 nil #'markdown-ascii--live-do-update (current-buffer))))

(defun markdown-ascii--live-do-update (src-buf)
  "Re-render preview from SRC-BUF if it is still live and live mode is on."
  (when (and (buffer-live-p src-buf)
             (buffer-local-value 'markdown-ascii-live-mode src-buf))
    (with-current-buffer src-buf
      (markdown-ascii-preview))))

;;; Scroll sync

(defun markdown-ascii--sync-point (from-buf to-buf)
  "Move TO-BUF's window point to match FROM-BUF's proportional line position.
Uses `set-window-point' which does not trigger `post-command-hook'."
  (let ((from-win (get-buffer-window from-buf t))
        (to-win   (get-buffer-window to-buf   t)))
    (when (and from-win to-win)
      (let* ((from-line  (with-current-buffer from-buf
                           (line-number-at-pos (window-point from-win))))
             (from-total (with-current-buffer from-buf
                           (line-number-at-pos (point-max))))
             (to-total   (with-current-buffer to-buf
                           (line-number-at-pos (point-max))))
             (to-line    (max 1 (round (* (/ (float from-line)
                                             (max 1.0 from-total))
                                          to-total))))
             (to-pos     (with-current-buffer to-buf
                           (save-excursion
                             (goto-char (point-min))
                             (forward-line (1- to-line))
                             (point)))))
        (set-window-point to-win to-pos)))))

(defun markdown-ascii--source-sync-post-command ()
  "Sync preview window position when point moves in the source buffer."
  (let ((preview-buf (get-buffer (format "*TextMD: %s*" (buffer-name)))))
    (when (buffer-live-p preview-buf)
      (markdown-ascii--sync-point (current-buffer) preview-buf))))

(defun markdown-ascii--preview-sync-post-command ()
  "Sync source window position when point moves in the preview buffer."
  (when (and (boundp 'markdown-ascii--source-buffer)
             (buffer-live-p markdown-ascii--source-buffer))
    (markdown-ascii--sync-point (current-buffer) markdown-ascii--source-buffer)))

;;;###autoload
(define-minor-mode markdown-ascii-live-mode
  "Auto-refresh TextMD preview 0.5 s after each edit, with scroll sync.
Enables `markdown-ascii-preview' on activation and cancels the timer on exit."
  :lighter " TextMD-Live"
  (if markdown-ascii-live-mode
      (progn
        (markdown-ascii-preview)
        (add-hook 'after-change-functions #'markdown-ascii--live-schedule    nil t)
        (add-hook 'post-command-hook      #'markdown-ascii--source-sync-post-command nil t)
        (let ((preview-buf (get-buffer (format "*TextMD: %s*" (buffer-name)))))
          (when (buffer-live-p preview-buf)
            (with-current-buffer preview-buf
              (add-hook 'post-command-hook #'markdown-ascii--preview-sync-post-command nil t)))))
    (when (timerp markdown-ascii--live-timer)
      (cancel-timer markdown-ascii--live-timer)
      (setq markdown-ascii--live-timer nil))
    (remove-hook 'after-change-functions #'markdown-ascii--live-schedule            t)
    (remove-hook 'post-command-hook      #'markdown-ascii--source-sync-post-command t)
    (let ((preview-buf (get-buffer (format "*TextMD: %s*" (buffer-name)))))
      (when (buffer-live-p preview-buf)
        (with-current-buffer preview-buf
          (remove-hook 'post-command-hook #'markdown-ascii--preview-sync-post-command t))))))

(provide 'markdown-ascii)
;;; markdown-ascii.el ends here
