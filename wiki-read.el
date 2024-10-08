;;; wiki-read.el --- Wikimedia reader         -*- lexical-binding: t; -*-

;; Copyright (C) 2024 813gan

;; URL:
;; Author: 813gan
;; Keywords:
;; Version: 1.0
;; Package: wiki-read
;; Package-Requires:

;;; Commentary:

;; # wiki-read.el

;;; Code:

(require 'json)
(require 'url)
(require 'url-parse)
(require 'subr-x)

(defvar wiki-read-url-template
  "https://%s/%s/api.php?action=parse&format=json&page=%s&formatversion=2")

(defun wiki-read--url-retrieve (url)
  "Wrapper around url-http that download `URL' without blocking thread."
  (let* ((parsed-url (if (url-p url) url (url-generic-parse-url url)))
	 (buf nil)
	 (status nil)
	 (cb (lambda (st &rest _) (setq status st buf (current-buffer)) )) )
    (url-retrieve parsed-url cb nil)
    (while (not status) (thread-yield) (sit-for 0.5))
    buf))

(defun wiki-read--fetch-url (api-url)
  "Fetch data about article for API `API-URL'."
  (let* ((response-buf (wiki-read--url-retrieve api-url))
	 (json-object-type 'plist)
	 (json-array-type 'list)
	 (resp (with-current-buffer response-buf (goto-char url-http-end-of-headers) (json-read)))
	 (resp-parsed (plist-get resp :parse))
	 (text (plist-get resp-parsed :text))
	 (title (plist-get resp-parsed :title)) )
    `((title . ,title) (text . ,text))) )

(defun wiki-read--shr-render-buffer (buffer target-buffer)
  "Modified `shr-render-buffer' that renders `BUFFER' to `TARGET-BUFFER'."
  (or (fboundp 'libxml-parse-html-region)
      (error "This function requires Emacs to be compiled with libxml2"))
  (pop-to-buffer target-buffer)
  (erase-buffer)
  (shr-insert-document
   (with-current-buffer buffer
     (libxml-parse-html-region (point-min) (point-max))))
  (goto-char (point-min)))

(defun wiki-read--render (api-url buffer)
  "Render article from `API-URL' inside `BUFFER'."
  (let-alist (wiki-read--fetch-url api-url)
    (let ((inhibit-read-only 't))
      (with-temp-buffer
	(insert .text)
	(wiki-read--shr-render-buffer (current-buffer) buffer)))
    ))

(defun wiki-read--get-api-prefix (host)
  "Get api prefix for `HOST'."
  (if (string-suffix-p "wikipedia.org" host)
      "w" ""))

(defun wiki-read-imenu--heading-p (my props)
  "Utility function."
  (seq-contains-p (ensure-list props) my 'equal) )

(defun wiki-read-imenu nil
  "Imenu source for wiki-read."
  (let (out)
    (goto-char (point-min))
    (while (setq match (text-property-search-forward 'face 'shr-h2 'wiki-read-imenu--heading-p 't))
      (push `(,(buffer-substring-no-properties (line-beginning-position) (line-end-position)) .
	      ,(prop-match-beginning match))
	    out)
      (forward-line))
    out))

(define-derived-mode wiki-mode special-mode "Wiki"
  "Major mode for displaying wikimedia articles."
  (setq-local imenu-create-index-function 'wiki-read-imenu))

(defun wiki-read--handle-redirections (url)
  (let ((parsed-url (url-generic-parse-url url)))
    (if (string-match-p ".*/Special:Search\\?" (url-filename parsed-url))
	(with-current-buffer (wiki-read--url-retrieve parsed-url) url-http-target-url)
      parsed-url)))

;;;###autoload
(defun wiki-read (url)
  "Render wikimedia article from `URL'."
  (let* ((parsed-url (wiki-read--handle-redirections url))
	 (filename (url-filename parsed-url))
	 (page-name (car (last (split-string filename "/"))))
	 (host (url-host parsed-url))
	 (wiki-prefix (wiki-read--get-api-prefix host))
	 (api-url (format wiki-read-url-template host wiki-prefix page-name))
	 (buffer (get-buffer-create (format "*wiki %s %s*" page-name host) ))
	 (inhibit-read-only 't))
    (with-current-buffer buffer
      (pp parsed-url)
      (wiki-mode)
      (erase-buffer)
      (insert "Loading " url " ...") )
    (make-thread (lambda nil (wiki-read--render api-url buffer)) "wiki-read") ))

(provide 'wiki-read)

;;; wiki-read.el ends here
