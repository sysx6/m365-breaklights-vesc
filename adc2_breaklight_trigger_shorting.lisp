; Simple ADC2 brake light test - minimal version that works
; Based on working brake_light_test.lisp logic
; Short ADC2 pins to trigger AUX light


;MINIMUM THRESHOLD 0.09-0.6
; Simple parameters
(def brake-adc-channel 2) ; ADC2 for brake input
(def aux-brake-port 1) ; AUX1 for brake light
(def brake-threshold 0.3) ; Threshold for ADC2 shorting
(def test-enabled 1)

; State variables
(def aux-brake-active 0)
(def last-brake-value 0)

; Simple brake light handler (same logic as working version)
(defun handle-brake-light (brake-value) {
    (if (= test-enabled 1)
        {
            (set 'last-brake-value brake-value)
            
            (if (> brake-value brake-threshold)
                ; Brake triggered - turn on light
                (if (= aux-brake-active 0)
                    {
                        (set-aux aux-brake-port 1)
                        (set 'aux-brake-active 1)
                        (print (str-from-n brake-value "Brake ON - ADC2: %.2f"))
                    }
                )
                ; Brake released - turn off light
                (if (= aux-brake-active 1)
                    {
                        (set-aux aux-brake-port 0)
                        (set 'aux-brake-active 0)
                        (print (str-from-n brake-value "Brake OFF - ADC2: %.2f"))
                    }
                )
            )
        }
    )
})

; Test function (same as working version)
(defun test-brake-light (test-value) {
    (print (str-from-n test-value "Testing with ADC2 value: %.2f"))
    (handle-brake-light test-value)
})

; Status function (same as working version)
(defun get-brake-status () {
    (print (str-from-n last-brake-value "Last ADC2 value: %.2f"))
    (print (str-from-n aux-brake-active "AUX brake active: %d"))
    (print (str-from-n brake-threshold "Brake threshold: %.2f"))
})

; Initialize AUX to OFF
(set-aux aux-brake-port 0)
(set 'aux-brake-active 0)

; Main monitoring loop - fixed ADC reading
(defun brake-monitor-loop () {
    (loopwhile t
        {
            ; Use get-adc instead of get-adc-decoded
            (var brake-value (get-adc brake-adc-channel))
            (handle-brake-light brake-value)
            (sleep 0.05)
        }
    )
})

; Simple startup message
(print "Simple ADC2 brake light test")
(print "Short ADC2 pins to trigger brake light")
(print "Commands: (test-brake-light 2.0) (get-brake-status)")
(print "Starting...")

; Start monitoring
(brake-monitor-loop) 