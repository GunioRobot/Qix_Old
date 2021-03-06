(in-package #:qix)

(defclass text-view ()
  ((cairo-surface
    :initform nil)
   (cairo-context
    :initform nil)
   (pango-context
    :initform nil)
   (pango-layout
    :initform nil)
   (data
    :accessor data
    :initform nil
    :initarg :data)
   (markup
    :accessor markup
    :initform nil
    :initarg :markup)
   (width
    :accessor width
    :initform (error "you must have a width")
    :initarg :width)
   (height
    :accessor height
    :initform (error "you must have a height!")
    :initarg :height)
   (storage-type
    :reader storage-type
    :initform :ARGB32
    :initarg :storage-type)
   (word-wrap
    :accessor word-wrap
    :initform :PANGO_WRAP_WORD
    :initarg :word-wrap)
   (text-font
    :accessor text-font
    :initform "Mono 10"
    :initarg :text-font)
   (page-x
    :accessor page-x
    :initform 0
    :initarg :page-x)
   (page-y
    :accessor page-y
    :initform 0
    :initarg :page-y)
   (text-width
    :accessor text-width
    :initform nil
    :initarg :text-width)
   (text-color
    :accessor text-color
    :initform '(255 255 255)
    :initarg :text-color)
   (background-color
    :accessor background-color
    :initform '(0 0 0)
    :initarg :background-color)))

(defmethod initialize-instance :after ((this text-view) &key)
  (initialize-cairo-surface this)
  (initialize-cairo-context this)
  (initialize-pango-context this)
  (initialize-pango-layout this))


(defmethod initialize-cairo-surface ((this text-view) &key)
  (release-cairo-surface this)
  (setf (slot-value this 'cairo-surface)
	(cairo:create-image-surface (storage-type this)
				    (width this)
				    (height this))))


(defmethod release-cairo-surface ((this text-view) &key)
  (with-slots ((csurf cairo-surface)) this
    (if csurf (cairo:destroy csurf))))


(defmethod initialize-cairo-context ((this text-view) &key)
  (release-cairo-context this)
  (setf (slot-value this 'cairo-context) (cairo:create-context (slot-value this 'cairo-surface))))


(defmethod release-cairo-context ((this text-view) &key)
  (with-slots ((cont cairo-context)) this
    (if cont (cairo:destroy cont))))


(defmethod get-cairo-context-pointer ((this text-view) &key)
  (cairo::get-pointer (slot-value this 'cairo-context)))


(defmethod initialize-pango-context ((this text-view) &key)
  (release-pango-context this)
  (setf (slot-value this 'pango-context)
  	(pango_cairo_create_context
  	 (get-cairo-context-pointer this))))


(defmethod release-pango-context ((this text-view) &key)
  (with-slots ((pcon pango-context)) this
    (if pcon (g_object_unref pcon))))


(defmethod initialize-pango-layout ((this text-view) &key)
  (release-pango-layout this)
  (setf (slot-value this 'pango-layout)
  	(pango_layout_new (slot-value this 'pango-context)))
  (with-slots ((layout pango-layout)
	       (width width)
	       (height height)) this
    (pango_layout_set_width layout (* width PANGO_SCALE))
    (pango_layout_set_height layout (* height PANGO_SCALE))
    (pango_layout_set_wrap layout (word-wrap this))))

(defmethod release-pango-layout ((this text-view) &key)
  (with-slots ((playout pango-layout)) this
    (if playout (g_object_unref playout))))


(defmethod release-text-view ((this text-view))
  (release-cairo-surface this)
  (release-cairo-context this)
  (release-pango-context this)
  (release-pango-layout this)
  (with-slots ((csurf cairo-surface)
	       (ccontext cairo-context)
	       (pcontext pango-context)
	       (layout pango-layout)
	       (data data)
	       (h height)
	       (w width)
	       (st storage-type)) this
    (setf data nil
	  w nil
	  h nil
	  st nil
	  cp nil
	  csurf nil
	  ccontext nil
	  pcontext nil
	  layout nil)))


(defmethod image-surface-data ((this text-view))
  (cairo:image-surface-get-data (slot-value this 'cairo-surface) :pointer-only t))

(defmethod write-to-png ((this text-view) path &key)
  (cairo:surface-write-to-png (slot-value this 'cairo-surface) path))

(defmethod draw-text ((this text-view) &optional cursor-position)
  (with-slots ((csurf cairo-surface)
	       (context cairo-context)
	       (pcontext pango-context)
	       (layout pango-layout)
	       (data data)
	       (h height)
	       (w width)
	       (st storage-type)) this

    (apply #'cairo:set-source-rgb (append (slot-value this 'background-color) (list context)))
    (cairo:paint context)
    (apply #'cairo:set-source-rgb (append (slot-value this 'text-color) (list context)))

    (let* ((desc (pango_font_description_from_string (text-font this))))
      
      (loop 
	 with pos = 0
	 for text in data
	 for i from 0
	 while (< pos (+ h (page-y this)))
	 do (let ((attrs (pango_attr_list_new)))

	      (cairo:move-to (page-x this) (- pos (page-y this)) context)
	      ;(format t "move to ~A~%" (- pos (page-y this)))
	      
	      (pango_layout_set_text layout text -1)
	      	      (pango_layout_set_attributes layout attrs)
	      (pango_layout_set_font_description layout desc)
	      (pango_cairo_update_layout (get-cairo-context-pointer this) layout)
	      				       
	      (pango_cairo_show_layout (get-cairo-context-pointer this) layout)
  
	      (when (and cursor-position
			 (= i (car cursor-position)))
		(let ((rect (get-cursor-pos layout (if (second cursor-position)
						       (second cursor-position)
						       (length text)))))
		  (cairo:with-context (context)
		    (cairo:move-to (first rect)
				   (+ pos (second rect)))
		    (cairo:line-to (first rect)
				   (+ pos (second rect) (fourth rect)))
		    (cairo:stroke))))

	      (multiple-value-bind (x y) (get-layout-size layout)
		(incf pos y))
	      (pango_attr_list_unref attrs)))

      (pango_font_description_free desc))
    csurf))


(defmethod setup-layout ((this text-view) text &key)
  (let* ((desc (pango_font_description_from_string (text-font this)))
	 (layout (slot-value this 'pango-layout))
	 (attrs (pango_attr_list_new)))
    
    (pango_layout_set_text layout text -1)
    (pango_layout_set_attributes layout attrs)
    (pango_layout_set_font_description layout desc)
    (pango_cairo_update_layout (get-cairo-context-pointer this) layout)
    
    (pango_attr_list_unref attrs)
    (pango_font_description_free desc)
    
    layout))


(defmethod cursor-forward ((this text-view) cursor)
  (let* ((line-number (car cursor))
	 (index (second cursor))
	 (text (nth line-number (data this))))
    (when text
      ;; If there is a cursor index use it...
      (if (second cursor)
	  (let* ((layout (setup-layout this text))
		 (new-index (move-cursor-visually layout index)))
	    (if (= index new-index)
		;; end of line...if there is a next line else, return same place..
		(if (nth (1+ line-number) (data this))
		    (list (1+ line-number) 0)
		    cursor)
		;; return the new pos...
		(list line-number new-index)))
	  
	  ;; otherwise go to the next line, if it exists...
	  (when (nth (1+ line-number) (data this))
	    (list (1+ line-number) 0))))))

	
(defmethod cursor-backward ((this text-view) cursor)
    (let* ((line-number (car cursor))
	   (index (second cursor)))
      (if (zerop index)
	  ;; the zero index...
	  (if (zerop line-number)
	      '(0 0)
	      (list (1- line-number)
		    (length (nth (1- line-number) (data this)))))

	  (let* ((text (nth line-number (data this)))
		 (layout (when text (setup-layout this text))))
		 (when layout (list line-number (move-cursor-visually layout index :forward nil)))))))
		 
	
