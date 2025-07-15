; ADC2 Pin Shorting Brake Light Test Script
; Use this with VESC tool to test AUX brake functionality using ADC2
; Short ADC2 pins to simulate brake input and trigger AUX light
; No M365 display required - just ADC2 input and AUX output

; Test parameters (configured for ADC2 pin shorting)
(def brake-adc-channel 2) ; ADC channel 2 for brake input
(def aux-brake-port 1) ; AUX port to use for brake light
(def brake-threshold 1.0) ; Threshold for pin shorting (1.0V - adjust if needed)
(def max-brake-voltage 3.3) ; Maximum expected voltage when pins are shorted
(def test-enabled 1) ; Enable/disable test mode

; State variables
(def aux-brake-active 0)
(def last-brake-value 0)
(def trigger-count 0) ; Count how many times brake was triggered

; Helper function to set AUX with timing
(defun set-auxtime (port state time) {
    (set-aux port state)
    (sleep time)
})

; Enhanced brake light handler with shorting detection
(defun handle-brake-light (brake-value) {
    (if (= test-enabled 1)
        {
            ; Store last brake value for debugging
            (set 'last-brake-value brake-value)
            
            ; Check if brake exceeds threshold (pin shorting detected)
            (if (> brake-value brake-threshold)
                ; Pin is shorted (brake active) - turn on light
                (if (= aux-brake-active 0)
                    {
                        (set-aux aux-brake-port 1)
                        (set 'aux-brake-active 1)
                        (set 'trigger-count (+ trigger-count 1))
                        (print (str-from-n brake-value "BRAKE TRIGGERED - ADC2 Value: %.2f V"))
                        (print (str-from-n trigger-count "Trigger count: %d"))
                    }
                )
                ; Pin is not shorted (brake released) - turn off light
                (if (= aux-brake-active 1)
                    {
                        (set-aux aux-brake-port 0)
                        (set 'aux-brake-active 0)
                        (print (str-from-n brake-value "BRAKE RELEASED - ADC2 Value: %.2f V"))
                    }
                )
            )
        }
    )
})

; Test function for manual testing
(defun test-brake-light (test-value) {
    (print (str-from-n test-value "Manual test with ADC2 value: %.2f V"))
    (handle-brake-light test-value)
})

; Function to simulate pin shorting
(defun simulate-short () {
    (print "Simulating ADC2 pin short (brake ON)")
    (handle-brake-light 3.0)
    (sleep 2.0)
    (print "Simulating ADC2 pin release (brake OFF)")
    (handle-brake-light 0.1)
})

; Status function with enhanced info
(defun get-brake-status () {
    (print "=== ADC2 Brake Light Status ===")
    (print (str-from-n last-brake-value "Last ADC2 value: %.2f V"))
    (print (str-from-n aux-brake-active "AUX brake light active: %d"))
    (print (str-from-n brake-threshold "Brake threshold: %.2f V"))
    (print (str-from-n trigger-count "Total triggers: %d"))
    (print (str-from-n aux-brake-port "AUX port: %d"))
    (print "===============================")
})

; Reset trigger count
(defun reset-triggers () {
    (set 'trigger-count 0)
    (print "Trigger count reset to 0")
})

; Calibration function to find optimal threshold
(defun calibrate-threshold () {
    (print "=== ADC2 Calibration ===")
    (print "1. Leave ADC2 pins open (not shorted)")
    (sleep 2.0)
    (var open-value (get-adc-decoded brake-adc-channel))
    (print (str-from-n open-value "Open circuit value: %.2f V"))
    
    (print "2. Now short ADC2 pins together...")
    (print "   Waiting 5 seconds for you to short the pins...")
    (sleep 5.0)
    (var short-value (get-adc-decoded brake-adc-channel))
    (print (str-from-n short-value "Shorted value: %.2f V"))
    
    (var suggested-threshold (+ open-value (/ (- short-value open-value) 2)))
    (print (str-from-n suggested-threshold "Suggested threshold: %.2f V"))
    (print "Use: (set 'brake-threshold X.X) to set new threshold")
    (print "========================")
})

; Initialize AUX to OFF state
(set-aux aux-brake-port 0)
(set 'aux-brake-active 0)

; Main monitoring loop
(defun brake-monitor-loop () {
    (loopwhile t
        {
            ; Read ADC2 value
            (var brake-value (get-adc-decoded brake-adc-channel))
            
            ; Handle brake light
            (handle-brake-light brake-value)
            
            ; Small delay to prevent overwhelming the system
            (sleep 0.1) ; 100ms delay for pin shorting detection
        }
    )
})

; Print startup message with ADC2 specific instructions
(print "=== ADC2 Pin Shorting Brake Light Test ===")
(print "")
(print "Hardware setup:")
(print "  - Connect brake light/LED to AUX1 output")
(print "  - ADC2 pins: short together to simulate brake")
(print "  - ADC2 Input: 3.3V max, 0V min")
(print "")
(print "Configuration:")
(print (str-from-n brake-adc-channel "Monitoring ADC channel: %d"))
(print (str-from-n aux-brake-port "Using AUX port: %d"))
(print (str-from-n brake-threshold "Brake threshold: %.2f V"))
(print "")
(print "Available commands:")
(print "  (test-brake-light 2.0) - Test with specific value")
(print "  (simulate-short) - Simulate pin shorting")
(print "  (get-brake-status) - Check current status")
(print "  (calibrate-threshold) - Auto-calibrate threshold")
(print "  (reset-triggers) - Reset trigger counter")
(print "  (set 'brake-threshold 1.5) - Change threshold")
(print "  (set 'test-enabled 0) - Disable test")
(print "")
(print "Instructions:")
(print "  1. Short ADC2 pins = Brake ON (light turns on)")
(print "  2. Open ADC2 pins = Brake OFF (light turns off)")
(print "")
(print "Starting ADC2 brake monitor loop...")

; Start the monitoring loop
(brake-monitor-loop) 