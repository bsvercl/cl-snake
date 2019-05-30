;;;; snake.lisp

(in-package #:snake)

(defparameter +segment-size+ 25)
(defparameter +screen-width+ 800)
(defparameter +screen-height+ 600)
(defparameter +segments-across-width+ (floor (/ +screen-width+ +segment-size+)))
(defparameter +segments-across-height+ (floor (/ +screen-height+ +segment-size+)))

(defparameter +snake-color+ (gamekit:vec4 1.0 0.75 0.5 1.0))
(defparameter +food-color+ (gamekit:vec4 0.5 0.25 1.0 1.0))
(defparameter +grid-color+ (gamekit:vec4 0.9 0.9 0.9 0.5))
(defparameter +transparent+ (gamekit:vec4))

(defun vec2= (this that)
  (and (= (gamekit:x this)
          (gamekit:x that))
       (= (gamekit:y this)
          (gamekit:y that))))

(defun mod-vec (this that)
  "MOD x and y of THIS by x and y of THAT."
  (gamekit:vec2 (mod (gamekit:x this) (gamekit:x that))
                (mod (gamekit:y this) (gamekit:y that))))

(defclass snake ()
  ((segments :initarg :segments :accessor segments-of)
   (direction :initarg :direction :accessor direction-of))
  (:documentation "The moving thing, usually user controlled."))

(defun make-snake (starting-position &optional (direction (gamekit:vec2)))
  "Creates a SNAKE with STARTING-POSITION and DIRECTION."
  (make-instance 'snake :segments (list starting-position)
                        :direction direction))

(defun snake-position (snake)
  "Head position of SNAKE."
  (first (segments-of snake)))

(defmethod (setf snake-position) (pos snake)
  (setf (first (segments-of snake)) pos))

(defun snake-tail (snake)
  "The rest of the SNAKE."
  (rest (segments-of snake)))

;; TODO(bsvercl): Don't allow Left<->Right Up<->Down
(defun change-direction (snake direction)
  "Modify DIRECTION of SNAKE with NEW-DIRECTION."
  (let ((new-direction (case direction
                         (:up (gamekit:vec2 0 1))
                         (:down (gamekit:vec2 0 -1))
                         (:left (gamekit:vec2 -1 0))
                         (:right (gamekit:vec2 1 0))
                         ;; We don't know that this is supposed to be.
                         (t (gamekit:vec2)))))
    (setf (direction-of snake) new-direction)))

(defun advance (snake ate-food-p)
  (with-slots (segments direction) snake
    (let* ((position (snake-position snake))
           ;; The position of the next head.
           (new-head (gamekit:add position direction))
           ;; If we ate the food we do not chop of the end of the SEGMENTS.
           (which-segments (if ate-food-p segments (butlast segments)))
           (new-segments (push new-head which-segments)))
      (setf segments new-segments)
      ;; Wrap SNAKE around the boundaries
      (setf (snake-position snake) (mod-vec (snake-position snake)
                                            (gamekit:vec2 +segments-across-width+
                                                          +segments-across-height+))))))

(defun hit-itself (snake)
  (let ((head-position (snake-position snake)))
    (loop for segment in (snake-tail snake)
          when (vec2= segment head-position)
            do (return-from hit-itself t))))

(defclass state () ())

(defgeneric update (state)
  (:method (state) (declare (ignore state))))
(defgeneric draw (state)
  (:method (state) (declare (ignore state))))
(defgeneric handle-key (state key)
  (:method (state key) (declare (ignore state key))))

(defclass main-menu-state (state)
  ((start-callback :initarg :start)))

(defmethod handle-key ((this main-menu-state) key)
  (with-slots (start-callback) this
    (when (eq key :space)
      (funcall start-callback))))

(defmethod draw ((this main-menu-state))
  (declare (ignore this))
  (let ((bounds (gamekit:calc-text-bounds "Welcome to SNAKE"))))
  (gamekit:draw-text "Welcome to SNAKE" (gamekit:vec2 (/ +screen-width+ 2)
                                                      (/ +screen-height+ 2)))
  (gamekit:draw-text "Press SPACE to play" (gamekit:add (gamekit:vec2 (/ +screen-width+ 2)
                                                                       (/ +screen-height+ 2))
                                                         (gamekit:vec2 0 -20))))

(defclass game-state (state)
  ((player :type snake :reader player-of)
   (food-pos :type gamekit:vec2 :reader food-pos-of)
   (score :type integer :initform 0 :reader score-of)
   (end-callback :initarg :end)))

(defmethod initialize-instance :after ((this game-state) &key)
  (with-slots (player food-pos) this
    (setf food-pos (new-food-pos))
    (setf player (make-snake (gamekit:vec2 (/ +segments-across-width+ 2)
                                           (/ +segments-across-height+ 2))))))

(defmethod update ((this game-state))
  (with-slots (player food-pos score) this
    (let* ((pos (snake-position player))
           (ate-food-p (vec2= food-pos pos)))
      (advance player ate-food-p)
      (when ate-food-p
        (setf food-pos (new-food-pos))
        (incf score 50))
      (when (hit-itself player)
        (setf score -1)))))

(defmethod draw ((this game-state))
  ;; TODO(bsvercl): Drop into CL-BODGE to speed this up.
  (loop for x from 0 below +segments-across-width+
        do (loop for y from 0 below +segments-across-height+
                 do (gamekit:draw-rect (gamekit:mult (gamekit:vec2 x y)
                                                     +segment-size+)
                                       +segment-size+ +segment-size+
                                       :fill-paint +transparent+
                                       :stroke-paint +grid-color+)))
  ;; Draw food
  (gamekit:draw-rect (gamekit:mult (food-pos-of this) +segment-size+)
                     +segment-size+ +segment-size+
                     :fill-paint +food-color+)
  ;; Draw SNAKE
  (dolist (pos (segments-of (player-of this)))
    (gamekit:draw-rect (gamekit:mult pos +segment-size+)
                       +segment-size+ +segment-size+
                       :fill-paint +snake-color+))
  ;; Draw SCORE
  (gamekit:draw-text (format nil "Score: ~A" (score-of this))
                     (gamekit:vec2 25 (- +screen-height+ 25))))

(defmethod handle-key ((state game-state) key)
  (with-slots (player) state
    (case key
      (:w (change-direction player :up))
      (:s (change-direction player :down))
      (:a (change-direction player :left))
      (:d (change-direction player :right))
      (:space (change-direction player :nothing)))))

(gamekit:defgame snake-game ()
  ((current-state :accessor state-of))
  (:viewport-title "Snake")
  (:viewport-width +screen-width+)
  (:viewport-height +screen-height+)
  (:act-rate 10))

(defun new-food-pos ()
  "Generates a new spot on the grid."
  (gamekit:vec2 (random +segments-across-width+)
                (random +segments-across-height+)))

(defmethod gamekit:post-initialize ((this snake-game))
  (with-slots (current-state) this
    (labels ((start ()
               (setf current-state (make-instance 'game-state :end #'end)))
             (end ()
               ;; TODO(bsvercl): Game over state.
               (print "uh oh, we haven't implemented this yet.")))
      (setf current-state (make-instance 'main-menu-state :start #'start)))
    (macrolet ((%binder (key &body body)
                 `(gamekit:bind-button ,key :pressed #'(lambda () ,@body))))
      ;; TODO(bsvercl): Make this prettier.
      (%binder :w (handle-key current-state :w))
      (%binder :s (handle-key current-state :s))
      (%binder :a (handle-key current-state :a))
      (%binder :d (handle-key current-state :d))
      (%binder :space (handle-key current-state :space))
      (%binder :q (handle-key current-state :q))
      (%binder :e (handle-key current-state :e)))))

(defmethod gamekit:act ((this snake-game))
  (with-slots (current-state) this
    (update current-state)))

(defmethod gamekit:draw ((this snake-game))
  (with-slots (current-state) this
    (draw current-state)))

(defun play (&optional blocking)
  (gamekit:start 'snake-game :viewport-resizable nil :blocking blocking))
