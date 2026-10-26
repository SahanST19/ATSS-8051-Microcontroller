ORG 0000H
        LJMP MAIN

        ; External Interrupt 0 (STOP Button / Emergency)
        ORG 0003H
        LJMP EMERGENCY_ISR

        ORG 0030H
MAIN:
        ; Initialize System Ports
        MOV P0, #00H            ; Turn off all motors initially
        MOV P1, #0FFH           ; Configure P1 as input (Keypad & Sensors)
        MOV P2, #00H            ; Turn off Actuators and Indicators
        MOV P3, #0FFH           ; Configure P3 as input (Buttons/Interrupts)

        ; Configure Interrupts
        SETB IT0                ; Set INT0 as falling-edge triggered
        SETB EX0                ; Enable External Interrupt 0
        SETB EA                 ; Enable Global Interrupts

        ; Configure Timers (Timer 0 for Ultrasonic, Timer 1 for PWM/Delay)
        MOV TMOD, #11H          ; Timer 0 and Timer 1 in 16-bit mode

SYSTEM_IDLE:
        SETB P2.5               ; Turn ON Green Light (System Ready)
        SETB P2.6               ; Ensure Red Light/Alarm is OFF (Active-Low)
        
WAIT_START:
        JB P3.6, WAIT_START     ; Wait until ON button (P3.6) is pressed

        ; Phase 1: User Input (Keypad Scanning)
READ_KEYPAD:
        MOV P1, #0FFH           ; Configure P1 as input
        CLR P1.0                ; Ground keypad rows 0-3
        CLR P1.1
        CLR P1.2
        CLR P1.3
        
        MOV A, P1
        ANL A, #070H            ; Mask keypad columns (P1.4, P1.5, P1.6)
        CJNE A, #070H, KEY_PRESS ; If a key is pressed, proceed
        SJMP READ_KEYPAD        ; Otherwise, keep waiting here endlessly
        
KEY_PRESS:
        ACALL DEBOUNCE_DELAY
        MOV A, P1
        ANL A, #070H
        CJNE A, #070H, STORE_KEY ; Confirm key press
        SJMP READ_KEYPAD

STORE_KEY:
        MOV R5, #01H            ; Store target location ID
        LJMP MOVE_GANTRY        ; Proceed to gantry movement after valid key

        ; Phase 2: Gantry Positioning (X and Y Axis)
MOVE_GANTRY:
Y_STEP_LOOP:
        MOV P0, #91H            ; DC Motor ON, Stepper 1001
        ACALL MOTOR_DELAY
        JB P1.7, STOP_GANTRY    ; Check Y-Row 1 Limit Switch

        MOV P0, #0C1H           ; DC Motor ON, Stepper 1100
        ACALL MOTOR_DELAY
        JB P1.7, STOP_GANTRY

        MOV P0, #61H            ; DC Motor ON, Stepper 0110
        ACALL MOTOR_DELAY
        JB P1.7, STOP_GANTRY

        MOV P0, #31H            ; DC Motor ON, Stepper 0011
        ACALL MOTOR_DELAY
        JB P1.7, STOP_GANTRY

        SJMP Y_STEP_LOOP        ; Continue stepping until limit switch is hit

STOP_GANTRY:
        MOV P0, #00H            ; Stop all motors

        ; Phase 3: Vertical Movement & Gripping
MEASURE_STACK:
        SETB P3.5               ; Trigger Ultrasonic Sensor
        ACALL MICRO_DELAY
        CLR P3.5
WAIT_ECHO:
        JNB P3.4, WAIT_ECHO     ; Wait for Echo pulse
        SETB TR0                ; Start Timer 0
WAIT_ECHO_END:
        JB P3.4, WAIT_ECHO_END
        CLR TR0                 ; Stop Timer 0

LOWER_Z:
        MOV P2, #09H            ; Step Mz Motor Downwards
        ACALL MOTOR_DELAY

        SETB P2.4               ; Turn ON Pneumatic Gripper (Relay)
        ACALL GRIP_DELAY        ; Wait for pressure to build

RAISE_Z:
        ; Step Mz Motor Upwards to safe height

        ; Phase 4: Delivery (Conveyor Belt)
DELIVER_TIRE:
        CLR P2.4                ; Turn OFF Gripper (Release Tire)

CONVEYOR_RUN:
        SETB P0.2               ; Mc Motor ON (Forward)
        CLR P0.3
        ACALL PWM_HALF_DELAY    ; Delay for ON time
        CLR P0.2                ; Mc Motor OFF
        ACALL PWM_HALF_DELAY    ; Delay for OFF time (50% Duty Cycle)
        
        JNB P2.7, CONVEYOR_RUN  ; Continue running if Conveyor IR (P2.7) is 0
        
        CLR P0.2                ; Stop motor when IR sensor is triggered
        LJMP SYSTEM_IDLE        ; Return to Idle State


; EMERGENCY INTERRUPT SERVICE ROUTINE (INT0)
EMERGENCY_ISR:
        CLR EA                  ; Disable further interrupts
        MOV P0, #00H            ; Immediate stop to all motors
        
        CLR P2.5                ; Turn OFF Green Light
        CLR P2.6                ; Turn ON Red Light and Buzzer (Active-Low)
        
EMERGENCY_WAIT:
        JB P3.7, EMERGENCY_WAIT ; Wait until Manual button (P3.7) is pressed
        
        SETB P2.6               ; Turn OFF Red Light and Buzzer
        MOV P0, #00H            ; Ensure all motors remain OFF
        
        SETB EA                 ; Re-enable interrupts
        LJMP MAIN               ; Reset system completely back to MAIN


; SUBROUTINES
STEP_SEQ:
        DB 09H, 0CH, 06H, 03H   ; Full-step sequence for Stepper Motors

DELAY_1S:
        MOV R3, #14             ; Loop counter for ~1s using Timer 1
D1S_LOOP:
        MOV TH1, #00H           ; Load Timer 1
        MOV TL1, #00H
        SETB TR1
WAIT_T1:
        JNB TF1, WAIT_T1
        CLR TR1
        CLR TF1
        DJNZ R3, D1S_LOOP
        RET

PWM_HALF_DELAY:
        MOV R4, #50             ; Delay for 50% PWM Duty Cycle
PWM_L:  DJNZ R4, PWM_L
        RET

MOTOR_DELAY:
        MOV R4, #15
MD_L2:  MOV R5, #0FFH
MD_L1:  DJNZ R5, MD_L1
        DJNZ R4, MD_L2
        RET

GRIP_DELAY:
        MOV R6, #0FFH
GD_L:   DJNZ R6, GD_L
        RET

DEBOUNCE_DELAY:
        MOV R7, #0FFH
DB_L:   DJNZ R7, DB_L
        RET
        
MICRO_DELAY:
        MOV R2, #0AH
M_DEL:  DJNZ R2, M_DEL
        RET
        
        END