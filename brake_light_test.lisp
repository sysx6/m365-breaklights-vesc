; Minimal brake light test script
; Use this with VESC tool to test AUX brake functionality
; No dashboard required - just brake ADC input and AUX output

; Test parameters (adjust these as needed)
(def brake-adc-channel 1) ; ADC channel for brake input (usually ADC1)
(def aux-brake-port 1) ; AUX port to use for brake light
(def brake-threshold 0.3) ; Minimum brake voltage to trigger light (0.3V)
(def test-enabled 1) ; Enable/disable test mode

; State variables
(def aux-brake-active 0)
(def last-brake-value 0)

; Helper function to set AUX with timing (from your AUX_on.lisp)
(defun set-auxtime (port state time) {
    (set-aux port state)
    (sleep time)
})

; Main brake light handler
(defun handle-brake-light (brake-value) {
    (if (= test-enabled 1)
        {
            ; Store last brake value for debugging
            (set 'last-brake-value brake-value)
            
            ; Check if brake exceeds threshold
            (if (> brake-value brake-threshold)
                ; Brake is pressed - turn on light
                (if (= aux-brake-active 0)
                    {
                        (set-aux aux-brake-port 1)
                        (set 'aux-brake-active 1)
                        (print (str-from-n brake-value "Brake ON - Value: %.2f"))
                    }
                )
                ; Brake is released - turn off light
                (if (= aux-brake-active 1)
                    {
                        (set-aux aux-brake-port 0)
                        (set 'aux-brake-active 0)
                        (print (str-from-n brake-value "Brake OFF - Value: %.2f"))
                    }
                )
            )
        }
    )
})

; Test function you can call manually from VESC tool
(defun test-brake-light (test-value) {
    (print (str-from-n test-value "Testing with brake value: %.2f"))
    (handle-brake-light test-value)
})

; Status function to check current state
(defun get-brake-status () {
    (print (str-from-n last-brake-value "Last brake value: %.2f"))
    (print (str-from-n aux-brake-active "AUX brake active: %d"))
    (print (str-from-n brake-threshold "Brake threshold: %.2f"))
})

; Initialize AUX to OFF state
(set-aux aux-brake-port 0)
(set 'aux-brake-active 0)

; Main loop - continuously monitor brake ADC
(defun brake-monitor-loop () {
    (loopwhile t
        {
            ; Read brake ADC value
            (var brake-value (get-adc-decoded brake-adc-channel))
            
            ; Handle brake light
            (handle-brake-light brake-value)
            
            ; Small delay to prevent overwhelming the system
            (sleep 0.05) ; 50ms delay
        }
    )
})

; Print startup message
(print "Brake light test initialized")
(print (str-from-n brake-adc-channel "Monitoring ADC channel: %d"))
(print (str-from-n aux-brake-port "Using AUX port: %d"))
(print (str-from-n brake-threshold "Brake threshold: %.2f V"))
(print "")
(print "Available commands:")
(print "  (test-brake-light 0.5) - Test with specific brake value")
(print "  (get-brake-status) - Check current status")
(print "  (set 'brake-threshold 0.4) - Change threshold")
(print "  (set 'test-enabled 0) - Disable test")
(print "")
(print "Starting brake monitor loop...")

; Start the monitoring loop
(brake-monitor-loop) 