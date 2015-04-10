;; -*- mode: common-lisp -*-

;; Copyright (c) 2015 The OpenWordNet-PT project
;; This program and the accompanying materials are made available
;; under the terms of the MIT License which accompanies this
;; distribution (see LICENSE)

(in-package :cl-wnbrowser)

;;; (setq hunchentoot:*show-lisp-errors-p* t)

(defun get-previous (n &optional (step 10))
  (- n step))

(defun get-next (n &optional (step 10))
  (+ n step))

(defun get-login ()
  (list :login (hunchentoot:session-value :login)))

(defun process-synset (synset)
  (cl-wnbrowser.templates:synset
   (append
    (get-login)
    synset)))

(defun process-nomlex (nomlex)
  (cl-wnbrowser.templates:nomlex
   (append (get-login) nomlex)))

(defun process-results (result)
  (cl-wnbrowser.templates:result result))

(defun process-activities (activities)
  (cl-wnbrowser.templates:activities activities))

(defun process-error (result)
  (cl-wnbrowser.templates:searcherror result))

(hunchentoot:define-easy-handler (get-root-handler-redirector :uri "/wn2") ()
  (hunchentoot:redirect "/wn/"))

(hunchentoot:define-easy-handler (get-root-handler :uri "/wn/") ()
  (cl-wnbrowser.templates:home
   (append
    (get-login)
    (list :githubid *github-client-id*))))


(hunchentoot:define-easy-handler (get-update-stats-handler
				  :uri "/wn/update-stats") ()
  (update-stat-cache)
  (if (string-equal "application/json" (hunchentoot:header-in* :accept))
      (progn
	(setf (hunchentoot:content-type*) "application/json")
	(with-output-to-string (s)
	  (yason:encode-plist (list :result "Done") s)))
      (hunchentoot:redirect "/wn/stats")))

(defun disable-caching ()
  (setf (hunchentoot:header-out :cache-control)
	"no-cache, no-store, must-revalidate")
  (setf (hunchentoot:header-out :pragma) "no-cache")
  (setf (hunchentoot:header-out :expires) 0))

(hunchentoot:define-easy-handler (get-stats-handler :uri "/wn/stats") ()
  (disable-caching)
  (cl-wnbrowser.templates:stats
   (append
    (stats-count-classes-plist)
    (stats-percent-complete-plist))))

(hunchentoot:define-easy-handler (search-cloudant-handler :uri "/wn/search")
    (term start bookmark debug
	  (fq_word_count_pt :parameter-type 'list)
	  (fq_word_count_en :parameter-type 'list)
	  (fq_rdftype :parameter-type 'list)
	  (fq_lexfile :parameter-type 'list))
  (setf (hunchentoot:content-type*) "text/html")
  (disable-caching)
  (if (is-synset-id term)
      (hunchentoot:redirect (format nil "/wn/synset?id=~a" term))
      (multiple-value-bind
	    (documents num-found facets nbookmark error)
	  (search-cloudant term (make-drilldown :rdf-type fq_rdftype
				     :lex-file fq_lexfile
				     :word-count-pt fq_word_count_pt
				     :word-count-en fq_word_count_en)
                           bookmark "search-documents")
	(if error
	    (process-error (list :error error :term term))
	    (let* ((start/i (if start (parse-integer start) 0)))
	      (hunchentoot:delete-session-value :ids)
	      (setf (hunchentoot:session-value :term) term)
	      (process-results
	       (list :debug debug :term term
		     :nbookmark nbookmark
		     :fq_rdftype fq_rdftype
		     :fq_lexfile fq_lexfile
		     :fq_word_count_pt fq_word_count_pt
		     :fq_word_count_en fq_word_count_en
		     :previous (get-previous start/i)
		     :next (get-next start/i)
		     :start start/i :numfound num-found
		     :facets facets :documents documents)))))))

(hunchentoot:define-easy-handler (search-activity-handler :uri "/wn/search-activities")
    (term start bookmark debug
	  (fq_type :parameter-type 'list)
	  (fq_action :parameter-type 'list)
	  (fq_status :parameter-type 'list)
	  (fq_doc_type :parameter-type 'list)
          (fq_provenance :parameter-type 'list)
          (fq_user :parameter-type 'list))
  (setf (hunchentoot:content-type*) "text/html")
  (disable-caching)
  (multiple-value-bind
        (documents num-found facets nbookmark error)
      (search-cloudant "*:*" (make-drilldown-activity
                             :type fq_type
                             :action fq_action
                             :status fq_status
                             :doc_type fq_doc_type
                             :provenance fq_provenance
                             :user fq_user)
                       bookmark "search-activities")
	(if error
	    (process-error (list :error error :term term))
	    (let* ((start/i (if start (parse-integer start) 0)))
	      (setf (hunchentoot:session-value :term) term)
	      (process-activities
	       (list :debug debug :term term
		     :nbookmark nbookmark
		     :fq_type fq_type
		     :fq_action fq_action
		     :fq_status fq_status
		     :fq_doc_type fq_doc_type
                     :fq_user fq_user
                     :fq_provenance fq_provenance
		     :previous (get-previous start/i)
		     :next (get-next start/i)
		     :start start/i :numfound num-found
		     :facets facets :documents documents))))))

(hunchentoot:define-easy-handler (get-synset-handler
				  :uri "/wn/synset") (id debug)
  (setf (hunchentoot:content-type*) "text/html")
  (disable-caching)
  (let* ((synset (get-synset id))
         (suggestions (get-suggestions id))
         (comments (get-comments id))
         (request-uri (hunchentoot:request-uri*))
	 (term (hunchentoot:session-value :term))
	 (ids (hunchentoot:session-value :ids)))
    (when (not (string-equal (lastcar ids) id))
      (setf (hunchentoot:session-value :ids) (append ids (list id))))
    (when request-uri
      (setf (hunchentoot:session-value :request-uri) request-uri))
    (process-synset
     (append
      (list
       :ids (last (hunchentoot:session-value :ids) *breadcrumb-size*)
       :term term
       :debug debug
       :comments comments
       :suggestions suggestions
       :githubid *github-client-id*
       :synset synset)
      synset))))

(hunchentoot:define-easy-handler (get-nomlex-handler
				  :uri "/wn/nomlex") (id debug term)
  (setf (hunchentoot:content-type*) "text/html")
  (disable-caching)
  (let ((nomlex (get-nomlex id))
	(term (hunchentoot:session-value :term)))
    (process-nomlex
     (append
      (list :term term
	    :debug debug
            :githubid *github-client-id*
	    :nomlex nomlex)
      nomlex))))

(hunchentoot:define-easy-handler (process-suggestion-handler
				  :uri "/wn/process-suggestion") (id doc_type type param)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (add-suggestion id doc_type type param login)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (process-comment-handler
				  :uri "/wn/process-comment") (id doc_type text)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (add-comment id doc_type text login)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (delete-suggestion-handler
				  :uri "/wn/delete-suggestion") (id)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (delete-suggestion id)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (accept-suggestion-handler
				  :uri "/wn/accept-suggestion") (id)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (accept-suggestion id)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (reject-suggestion-handler
				  :uri "/wn/reject-suggestion") (id)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (reject-suggestion id)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (delete-comment-handler
				  :uri "/wn/delete-comment") (id)
  (let ((login (hunchentoot:session-value :login))
        (request-uri (hunchentoot:session-value :request-uri)))
    (if login
        (progn
          (delete-comment id)
          (if request-uri
              (hunchentoot:redirect request-uri)
              (hunchentoot:redirect "/wn/")))
        (progn
          (setf (hunchentoot:content-type*) "text/html")
          (format nil "invalid login")))))

(hunchentoot:define-easy-handler (pending-suggestions-handler
				  :uri "/wn/activity") ()
  (let ((activity (get-activity)))
    (setf (hunchentoot:content-type*) "text/html")
    (disable-caching)
    (cl-wnbrowser.templates:activity
     (list :activities activity))))

(hunchentoot:define-easy-handler (github-callback-handler
				  :uri "/wn/callback") (code)
  (let ((access-token (get-access-token code))
        (request-uri (hunchentoot:session-value :request-uri)))
    (setf (hunchentoot:session-value :login) (get-user-login (get-user access-token)))
    (if request-uri
        (hunchentoot:redirect request-uri)
        (hunchentoot:redirect "/wn/"))))

(defun start-server (&optional (port 4243))
  (push (hunchentoot:create-folder-dispatcher-and-handler
	 "/wn/st/"
	 (merge-pathnames #p"static/" *basedir*)) hunchentoot:*dispatch-table*)
  (hunchentoot:start
   (make-instance 'hunchentoot:easy-acceptor
		  :access-log-destination (merge-pathnames #p"wn.log" *basedir*)
		  :port port)))
