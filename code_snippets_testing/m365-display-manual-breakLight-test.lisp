; M365 dashboard compability lisp script v1.0 with M365 Brake Light - SIMPLIFIED
; Based on original v1.0 by Netzpfuscher and 1zuna
; Added AUX brake light functionality that works with M365 display brake signal
; Removed code server dependency for single VESC setups
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
(def sport-watts 700)
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

(if (= software-adc 1)
    (app-adc-detach 3 1)
    (app-adc-detach 3 0)
)

; M365 brake light handler
(defun handle-m365-brake-light (brake-value) {
    (if (= aux-brake-enabled 1)
        {
            (set 'last-m365-brake-value brake-value)

            (if (> brake-value m365-brake-threshold)
                ; Brake triggered - turn on light
                (if (= aux-brake-active 0)
                    {
                        (set-aux aux-brake-port 1)
                        (set 'aux-brake-active 1)
                        (print (str-from-n brake-value "M365 Brake ON - Value: %.2fV"))
                    }
                )
                ; Brake released - turn off light
                (if (= aux-brake-active 1)
                    {
                        (set-aux aux-brake-port 0)
                        (set 'aux-brake-active 0)
                        (print (str-from-n brake-value "M365 Brake OFF - Value: %.2fV"))
                    }
                )
            )
        }
    )
})

; Test functions
(defun test-m365-brake-light (test-value) {
    (print (str-from-n test-value "Testing M365 brake with value: %.2fV"))
    (handle-m365-brake-light test-value)
})

(defun get-m365-brake-status () {
    (print "=== M365 Brake Light Status ===")
    (print (str-from-n last-m365-brake-value "Last M365 brake value: %.2fV"))
    (print (str-from-n aux-brake-active "AUX brake light active: %d"))
    (print (str-from-n m365-brake-threshold "M365 brake threshold: %.2fV"))
    (print (str-from-n aux-brake-enabled "Brake light enabled: %d"))
    (print "==============================")
})

(defun adc-input(buffer) ; Frame 0x65
    {
        (let ((current-speed (* (get-speed) 3.6))
            (throttle (/(bufget-u8 uart-buf 4) 77.2)) ; 255/3.3 = 77.2
            (brake (/(bufget-u8 uart-buf 5) 77.2)))
            {
                (if (< throttle 0)
                    (setf throttle 0))
                (if (> throttle 3.3)
                    (setf throttle 3.3))
                (if (< brake 0)
                    (setf brake 0))
                (if (> brake 3.3)
                    (setf brake 3.3))

                ; Handle M365 brake light based on brake signal from display
                (handle-m365-brake-light brake)

                ; Pass through throttle and brake to VESC
                (app-adc-override 0 throttle)
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

(defun configure-speed(speed watts current fw)
    {
        (conf-set 'max-speed speed)
        (conf-set 'l-watt-max watts)
        (conf-set 'l-current-max-scale current)
        (conf-set 'foc-fw-current-max fw)
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

; Apply mode on start-up
(apply-mode)

; Print startup message
(print "M365 Dashboard V1 with M365 Brake Light - SIMPLIFIED")
(print "Brake light triggered by M365 display brake signal")
(print "Single VESC setup (no CAN required)")
(print "Commands:")
(print "  (test-m365-brake-light 0.5) - Test brake light")
(print "  (get-m365-brake-status) - Check brake status")
(print "  (set 'aux-brake-enabled 0) - Disable brake light")

; Spawn UART reading frames thread
(spawn 150 read-frames)
(button-logic) ; Start button logic in main thread - this will block the main thread