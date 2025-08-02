; M365 dashboard compability lisp script v1.0 with M365 Brake Light - SAFE VERSION v2 - SPEED MODE FIXED
; Based on original v1.0 by Netzpfuscher and 1zuna
; Added AUX brake light functionality that works with M365 display brake signal
; IMPROVED SAFETY FEATURES: 
; - Throttle cutoff with hysteresis to prevent flickering
; - Better signal filtering
; - Clearer logging of throttle vs brake duty cycles
; FIXED: Speed mode parameter propagation to CAN devices
; UART Wiring: red=5V black=GND yellow=COM-TX (UART-HDX) green=COM-RX (button)+3.3V with 1K Resistor

; -> User parameters (change these to your needs)
(def software-adc 1)
(def min-adc-throttle 0.1)
(def min-adc-brake 0.1)

(def show-batt-in-idle 1)
(def min-speed 0)
(def button-safety-speed (/ 0.1 3.6)) ; disabling button above 0.1 km/h (due to safety reasons)

; M365 brake light parameters
(def aux-brake-enabled 1) ; Enable/disable M365 brake light functionality
(def aux-brake-port 1) ; AUX port for brake light
(def m365-brake-threshold 0.3) ; Threshold for M365 brake signal (in volts)
(def m365-brake-hysteresis 0.1) ; Hysteresis to prevent flickering (release threshold = threshold - hysteresis)

; Safety parameters with improved hysteresis
(def brake-cutoff-threshold 0.15) ; Throttle cutoff threshold
(def brake-cutoff-release-threshold 0.1) ; Release threshold (prevents flickering)
(def brake-cutoff-enabled 1) ; Enable/disable throttle cutoff safety feature

; Signal filtering
(def brake-filter-alpha 0.3) ; Low-pass filter coefficient (0.0 = no filtering, 1.0 = no response)
(def throttle-filter-alpha 0.2) ; Low-pass filter coefficient for throttle

; Speed modes (km/h, watts, current scale)
(def eco-speed (/ 7 3.6))
(def eco-current 0.6)
(def eco-watts 400)
(def eco-fw 0)
(def drive-speed (/ 17 3.6))
(def drive-current 0.7)
(def drive-watts 500)
(def drive-fw 0)
(def sport-speed (/ 21 3.6))
(def sport-current 1.0)
(def sport-watts 15000) ; Updated to 15kW
(def sport-fw 0)

; Secret speed modes. To enable, press the button 2 times while holding break and throttle at the same time.
(def secret-enabled 1)
(def secret-eco-speed (/ 27 3.6))
(def secret-eco-current 0.8)
(def secret-eco-watts 1200)
(def secret-eco-fw 0)
(def secret-drive-speed (/ 47 3.6))
(def secret-drive-current 0.9)
(def secret-drive-watts 1500)
(def secret-drive-fw 0)
(def secret-sport-speed (/ 1000 3.6)) ; 1000 km/h easy
(def secret-sport-current 1.0)
(def secret-sport-watts 1500000)
(def secret-sport-fw 10)

; -> Code starts here (DO NOT CHANGE ANYTHING BELOW THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING)

; Packet handling
(uart-start 115200 'half-duplex)
(gpio-configure 'pin-rx 'pin-mode-in-pu)
(def tx-frame (array-create 14))
(bufset-u16 tx-frame 0 0x55AA)
(bufset-u16 tx-frame 2 0x0821)
(bufset-u16 tx-frame 4 0x6400)
(def uart-buf (array-create 64))

; Button handling
(def presstime (systime))
(def presses 0)

; Mode states
(def off 0)
(def lock 0)
(def speedmode 4)
(def light 0)
(def unlock 0)

; Sound feedback
(def feedback 0)

; M365 brake light state variables
(def aux-brake-active 0)
(def last-m365-brake-value 0)

; Safety state variables
(def throttle-cutoff-active 0)
(def last-throttle-cutoff-time 0)
(def safety-activation-count 0)

; Signal filtering variables
(def filtered-brake-value 0)
(def filtered-throttle-value 0)
(def last-raw-brake 0)
(def last-raw-throttle 0)

(if (= software-adc 1)
    (app-adc-detach 3 1)
    (app-adc-detach 3 0)
)

; Signal filtering function
(defun apply-filter (current-value last-filtered alpha) {
    (+ (* alpha current-value) (* (- 1.0 alpha) last-filtered))
})

; M365 brake light handler with hysteresis
(defun handle-m365-brake-light (brake-value) {
    (if (= aux-brake-enabled 1)
        {
            (set 'last-m365-brake-value brake-value)

            (if (= aux-brake-active 0)
                ; Light is OFF - check if we should turn it ON
                (if (> brake-value m365-brake-threshold)
                    {
                        (set-aux aux-brake-port 1)
                        (set 'aux-brake-active 1)
                        (print (str-from-n brake-value "M365 Brake LIGHT ON - Value: %.2fV"))
                    }
                )
                ; Light is ON - check if we should turn it OFF (with hysteresis)
                (if (< brake-value (- m365-brake-threshold m365-brake-hysteresis))
                    {
                        (set-aux aux-brake-port 0)
                        (set 'aux-brake-active 0)
                        (print (str-from-n brake-value "M365 Brake LIGHT OFF - Value: %.2fV"))
                    }
                )
            )
        }
    )
})

; Improved throttle cutoff safety handler with hysteresis
(defun handle-throttle-cutoff (brake-value throttle-value) {
    (if (= brake-cutoff-enabled 1)
        {
            (if (= throttle-cutoff-active 0)
                ; Cutoff is OFF - check if we should activate it
                (if (> brake-value brake-cutoff-threshold)
                    {
                        (set 'throttle-cutoff-active 1)
                        (set 'last-throttle-cutoff-time (systime))
                        (set 'safety-activation-count (+ safety-activation-count 1))
                        (print (str-from-n brake-value "SAFETY: THROTTLE CUTOFF ACTIVATED - Brake: %.2fV"))
                        (print (str-from-n throttle-value "SAFETY: Original throttle was: %.2fV"))
                        0 ; Return 0 throttle
                    }
                    throttle-value ; Return original throttle
                )
                ; Cutoff is ON - check if we should deactivate it (with hysteresis)
                (if (< brake-value brake-cutoff-release-threshold)
                    {
                        (set 'throttle-cutoff-active 0)
                        (print (str-from-n brake-value "SAFETY: THROTTLE CUTOFF DEACTIVATED - Brake: %.2fV"))
                        throttle-value ; Return original throttle
                    }
                    0 ; Still active, return 0 throttle
                )
            )
        }
        throttle-value ; Safety disabled, return original throttle
    )
})

; Test functions
(defun test-m365-brake-light (test-value) {
    (print (str-from-n test-value "Testing M365 brake with value: %.2fV"))
    (handle-m365-brake-light test-value)
})

(defun test-throttle-cutoff (brake-value throttle-value) {
    (print (str-from-n brake-value "Testing throttle cutoff - Brake: %.2fV"))
    (print (str-from-n throttle-value "Testing throttle cutoff - Throttle: %.2fV"))
    (var result (handle-throttle-cutoff brake-value throttle-value))
    (print (str-from-n result "Result throttle: %.2fV"))
    result
})

(defun get-m365-brake-status () {
    (print "=== M365 Brake Light Status ===")
    (print (str-from-n last-m365-brake-value "Last M365 brake value: %.2fV"))
    (print (str-from-n filtered-brake-value "Filtered brake value: %.2fV"))
    (print (str-from-n aux-brake-active "AUX brake light active: %d"))
    (print (str-from-n m365-brake-threshold "M365 brake threshold: %.2fV"))
    (print (str-from-n aux-brake-enabled "Brake light enabled: %d"))
    (print "==============================")
})

(defun get-safety-status () {
    (print "=== Safety Status ===")
    (print (str-from-n brake-cutoff-enabled "Throttle cutoff enabled: %d"))
    (print (str-from-n brake-cutoff-threshold "Brake cutoff threshold: %.2fV"))
    (print (str-from-n brake-cutoff-release-threshold "Brake cutoff release threshold: %.2fV"))
    (print (str-from-n throttle-cutoff-active "Throttle cutoff active: %d"))
    (print (str-from-n safety-activation-count "Safety activations: %d"))
    (print (str-from-n (/ (- (systime) last-throttle-cutoff-time) 1000) "Time since last cutoff: %.1fs"))
    (print "=====================")
})

(defun get-signal-status () {
    (print "=== Signal Status ===")
    (print (str-from-n last-raw-brake "Raw brake: %.2fV"))
    (print (str-from-n filtered-brake-value "Filtered brake: %.2fV"))
    (print (str-from-n last-raw-throttle "Raw throttle: %.2fV"))
    (print (str-from-n filtered-throttle-value "Filtered throttle: %.2fV"))
    (print (str-from-n (get-duty) "Current duty cycle: %.2f"))
    (print (str-from-n (get-current) "Current motor current: %.2fA"))
    (print "====================")
})

; NEW: Speed mode debugging function
(defun get-speed-mode-status () {
    (print "=== Speed Mode Status ===")
    (print (str-from-n speedmode "Current speedmode: %d"))
    (if (= speedmode 1) (print "Mode: DRIVE"))
    (if (= speedmode 2) (print "Mode: ECO"))
    (if (= speedmode 4) (print "Mode: SPORT"))
    (print (str-from-n unlock "Unlock mode: %d"))
    (print (str-from-n off "Off state: %d"))
    (print (str-from-n lock "Lock state: %d"))
    (print "Current VESC Settings:")
    (print (str-from-n (conf-get 'max-speed) "max-speed: %.2f m/s") (str-from-n (* (conf-get 'max-speed) 3.6) " (%.1f km/h)"))
    (print (str-from-n (conf-get 'l-watt-max) "l-watt-max: %.0fW"))
    (print (str-from-n (conf-get 'l-current-max-scale) "l-current-max-scale: %.2f"))
    (print "========================")
})

(defun adc-input(buffer) ; Frame 0x65
    {
        (let ((current-speed (* (get-speed) 3.6))
            (raw-throttle (/(bufget-u8 uart-buf 4) 77.2)) ; 255/3.3 = 77.2
            (raw-brake (/(bufget-u8 uart-buf 5) 77.2)))
            {
                ; Clamp raw values
                (if (< raw-throttle 0)
                    (setf raw-throttle 0))
                (if (> raw-throttle 3.3)
                    (setf raw-throttle 3.3))
                (if (< raw-brake 0)
                    (setf raw-brake 0))
                (if (> raw-brake 3.3)
                    (setf raw-brake 3.3))

                ; Store raw values for monitoring
                (set 'last-raw-throttle raw-throttle)
                (set 'last-raw-brake raw-brake)

                ; Apply signal filtering
                (set 'filtered-throttle-value (apply-filter raw-throttle filtered-throttle-value throttle-filter-alpha))
                (set 'filtered-brake-value (apply-filter raw-brake filtered-brake-value brake-filter-alpha))

                ; Use filtered values for control logic
                (var throttle filtered-throttle-value)
                (var brake filtered-brake-value)

                ; Handle M365 brake light based on filtered brake signal
                (handle-m365-brake-light brake)

                ; SAFETY FEATURE: Apply throttle cutoff when brake is active
                (var safe-throttle (handle-throttle-cutoff brake throttle))

                ; Debug output (uncomment for detailed logging)
                ; (if (> brake 0.1)
                ;     (print (str-from-n brake "Brake: %.2fV") (str-from-n safe-throttle " SafeThrottle: %.2fV"))
                ; )

                ; Pass through processed throttle and brake to VESC
                (app-adc-override 0 safe-throttle)
                (app-adc-override 1 brake)
            }
        )
    }
)

(defun handle-features()
    {
        (if (or (or (= off 1) (= lock 1) (< (* (get-speed) 3.6) min-speed)))
            (if (not (app-is-output-disabled)) ; Disable output when scooter is turned off
                {
                    (app-adc-override 0 0)
                    (app-adc-override 1 0)
                    (app-disable-output -1)
                    (set-current 0)
                    ; Turn off AUX brake light when scooter is off
                    (if (= aux-brake-active 1)
                        {
                            (set-aux aux-brake-port 0)
                            (set 'aux-brake-active 0)
                        }
                    )
                    ; Reset throttle cutoff when scooter is off
                    (set 'throttle-cutoff-active 0)
                }

            )
            (if (app-is-output-disabled) ; Enable output when scooter is turned on
                (app-disable-output 0)
            )
        )

        (if (= lock 1)
            {
                (set-current-rel 0) ; No current input when locked
                (if (> (* (get-speed) 3.6) min-speed)
                    (set-brake-rel 1) ; Full power brake
                    (set-brake-rel 0) ; No brake
                )
            }
        )
    }
)

(defun update-dash(buffer) ; Frame 0x64
    {
        (var current-speed (* (get-speed) 3.6))
        (var battery (*(get-batt) 100))

        ; mode field (1=drive, 2=eco, 4=sport, 8=charge, 16=off, 32=lock)
        (if (= off 1)
            (bufset-u8 tx-frame 6 16)
            (if (= lock 1)
                (bufset-u8 tx-frame 6 32) ; lock display
                (if (or (> (get-temp-fet) 60) (> (get-temp-mot) 60)) ; temp icon will show up above 60 degree
                    (bufset-u8 tx-frame 6 (+ 128 speedmode))
                    (bufset-u8 tx-frame 6 speedmode)
                )
            )
        )

        ; batt field
        (bufset-u8 tx-frame 7 battery)

        ; light field
        (if (= off 0)
            (bufset-u8 tx-frame 8 light)
            (bufset-u8 tx-frame 8 0)
        )

        ; beep field
        (if (= lock 1)
            (if (> current-speed min-speed)
                (bufset-u8 tx-frame 9 1) ; beep lock
                (bufset-u8 tx-frame 9 0))
            (if (> feedback 0)
                {
                    (bufset-u8 tx-frame 9 1)
                    (set 'feedback (- feedback 1))
                }
                (bufset-u8 tx-frame 9 0)
            )
        )

        ; speed field
        (if (= (+ show-batt-in-idle unlock) 2)
            (if (> current-speed 1)
                (bufset-u8 tx-frame 10 current-speed)
                (bufset-u8 tx-frame 10 battery))
            (bufset-u8 tx-frame 10 current-speed)
        )

        ; error field
        (bufset-u8 tx-frame 11 (get-fault))

        ; calc crc
        (var crc 0)
        (looprange i 2 12
            (set 'crc (+ crc (bufget-u8 tx-frame i))))
        (var c-out (bitwise-xor crc 0xFFFF))
        (bufset-u8 tx-frame 12 c-out)
        (bufset-u8 tx-frame 13 (shr c-out 8))

        ; write
        (uart-write tx-frame)
    }
)

(defun read-frames()
    (loopwhile t
        {
            (uart-read-bytes uart-buf 3 0)
            (if (= (bufget-u16 uart-buf 0) 0x55aa)
                {
                    (var len (bufget-u8 uart-buf 2))
                    (var crc len)
                    (if (and (> len 0) (< len 60)) ; max 64 bytes
                        {
                            (uart-read-bytes uart-buf (+ len 4) 0)
                            (looprange i 0 len
                                (set 'crc (+ crc (bufget-u8 uart-buf i))))
                            (if (=(+(shl(bufget-u8 uart-buf (+ len 2))8) (bufget-u8 uart-buf (+ len 1))) (bitwise-xor crc 0xFFFF))
                                (handle-frame (bufget-u8 uart-buf 1))
                            )
                        }
                    )
                }
            )
        }
    )
)

(defun handle-frame(code)
    {
        (if (and (= code 0x65) (= software-adc 1))
            (adc-input uart-buf)
        )

        (update-dash uart-buf)
    }
)

(defun handle-button()
    (if (= presses 1) ; single press
        (if (= off 1) ; is it off? turn on scooter again
            {
                (set 'off 0) ; turn on
                (set 'feedback 1) ; beep feedback
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode) ; Apply mode on start-up
                (stats-reset) ; reset stats when turning on
            }
            (set 'light (bitwise-xor light 1)) ; toggle light
        )
        (if (>= presses 2) ; double press
            {
                (if (> (get-adc 1) min-adc-brake) ; if brake is pressed
                    (if (and (= secret-enabled 1) (> (get-adc 0) min-adc-throttle))
                        {
                            (set 'unlock (bitwise-xor unlock 1))
                            (set 'feedback 2) ; beep 2x
                            (apply-mode)
                        }
                        {
                            (set 'unlock 0)
                            (apply-mode)
                            (set 'lock (bitwise-xor lock 1)) ; lock on or off
                            (set 'feedback 1) ; beep feedback
                        }
                    )
                    {
                        (if (= lock 0)
                            {
                                (cond
                                    ((= speedmode 1) (set 'speedmode 4))
                                    ((= speedmode 2) (set 'speedmode 1))
                                    ((= speedmode 4) (set 'speedmode 2))
                                )
                                (apply-mode)
                            }
                        )
                    }
                )
            }
        )
    )
)

(defun handle-holding-button()
    {
        (if (= (+ lock off) 0) ; it is locked and off?
            {
                (set 'unlock 0) ; Disable unlock on turn off
                (apply-mode)
                (set 'off 1) ; turn off
                (set 'light 0) ; turn off light
                (set 'feedback 1) ; beep feedback
            }
        )
    }
)

(defun reset-button()
    {
        (set 'presstime (systime)) ; reset press time again
        (set 'presses 0)
    }
)

; Speed mode implementation - simplified for single VESC

(defun apply-mode()
    (if (= unlock 0)
        (if (= speedmode 1)
            (configure-speed drive-speed drive-watts drive-current drive-fw)
            (if (= speedmode 2)
                (configure-speed eco-speed eco-watts eco-current eco-fw)
                (if (= speedmode 4)
                    (configure-speed sport-speed sport-watts sport-current sport-fw)
                )
            )
        )
        (if (= speedmode 1)
            (configure-speed secret-drive-speed secret-drive-watts secret-drive-current secret-drive-fw)
            (if (= speedmode 2)
                (configure-speed secret-eco-speed secret-eco-watts secret-eco-current secret-eco-fw)
                (if (= speedmode 4)
                    (configure-speed secret-sport-speed secret-sport-watts secret-sport-current secret-sport-fw)
                )
            )
        )
    )
)

; FIXED: Now uses set-param to propagate settings to all CAN devices
(defun configure-speed(speed watts current fw)
    {
        (print (str-from-n speed "SPEED MODE: Setting max-speed to %.2f m/s") (str-from-n (* speed 3.6) " (%.1f km/h)"))
        (print (str-from-n watts "SPEED MODE: Setting l-watt-max to %.0fW"))
        (print (str-from-n current "SPEED MODE: Setting l-current-max-scale to %.2f"))
        (set-param 'max-speed speed)
        (set-param 'l-watt-max watts)
        (set-param 'l-current-max-scale current)
        (set-param 'foc-fw-current-max fw)
    }
)

; NEW: Function to set parameters both locally and on all CAN devices
(defun set-param (param value)
    {
        (conf-set param value)
        (loopforeach id (can-list-devs)
            (looprange i 0 5 {
                (if (eq (rcode-run id 0.1 `(conf-set (quote ,param) ,value)) t) (break t))
                false
            })
        )
    }
)

(defun button-logic()
    {
        ; Assume button is not pressed by default
        (var buttonold 0)
        (loopwhile t
            {
                (var button (gpio-read 'pin-rx))
                (sleep 0.05) ; wait 50 ms to debounce
                (var buttonconfirm (gpio-read 'pin-rx))
                (if (not (= button buttonconfirm))
                    (set 'button 0)
                )

                (if (> buttonold button)
                    {
                        (set 'presses (+ presses 1))
                        (set 'presstime (systime))
                    }
                    (button-apply button)
                )

                (set 'buttonold button)
                (handle-features)
            }
        )
    }
)

(defun button-apply(button)
    {
        (var time-passed (- (systime) presstime))
        (var is-active (or (= off 1) (<= (get-speed) button-safety-speed)))

        (if (> time-passed 2500) ; after 2500 ms
            (if (= button 0) ; check button is still pressed
                (if (> time-passed 6000) ; long press after 6000 ms
                    {
                        (if is-active
                            (handle-holding-button)
                        )
                        (reset-button) ; reset button
                    }
                )
                (if (> presses 0) ; if presses > 0
                    {
                        (if is-active
                            (handle-button) ; handle button presses
                        )
                        (reset-button) ; reset button
                    }
                )
            )
        )
    }
)

; Initialize AUX brake light
(set-aux aux-brake-port 0)
(set 'aux-brake-active 0)

; Initialize safety systems
(set 'throttle-cutoff-active 0)
(set 'last-throttle-cutoff-time 0)
(set 'safety-activation-count 0)

; Initialize signal filtering
(set 'filtered-brake-value 0)
(set 'filtered-throttle-value 0)
(set 'last-raw-brake 0)
(set 'last-raw-throttle 0)

; Apply mode on start-up
(apply-mode)

; Print startup message
(print "M365 Dashboard V1 with M365 Brake Light - SAFE VERSION v2 - SPEED MODE FIXED")
(print "IMPROVED SAFETY FEATURES:")
(print "- Throttle cutoff with hysteresis (no flickering)")
(print "- Signal filtering for stable operation")
(print "- Better brake light control")
(print "- Enhanced debugging capabilities")
(print "- FIXED: Speed mode parameter propagation to CAN devices")
(print "Commands:")
(print "  (test-m365-brake-light 0.5) - Test brake light")
(print "  (test-throttle-cutoff 0.4 1.0) - Test throttle cutoff")
(print "  (get-m365-brake-status) - Check brake status")
(print "  (get-safety-status) - Check safety status")
(print "  (get-signal-status) - Check signal values and motor status")
(print "  (get-speed-mode-status) - Check current speed mode and VESC settings")
(print "  (set 'brake-cutoff-enabled 0) - Disable throttle cutoff")
(print "  (set 'brake-cutoff-threshold 0.2) - Change cutoff threshold")
(print "  (set 'brake-cutoff-release-threshold 0.1) - Change release threshold")

; Spawn UART reading frames thread
(spawn 150 read-frames)
(button-logic) ; Start button logic in main thread - this will block the main thread 