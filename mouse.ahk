;The SendInput DllCall is specifically 32-bit. So check for the correct bitness of AutoHotkey and if not, try to run the right one.
If (A_PtrSize=8){
    SplitPath, A_AhkPath,,Dir
    Run %Dir%\AutoHotkeyU32.exe %A_ScriptFullPath%
    ExitApp
}

;Call below to accelerate the mouse input. The first two parameters are the integer factors of artificial amplification added on top of the physical input.
;The first is for horizontal/x-axis movement, the second for vertical/y-axis movement.
new MouseAccelerator (0, 3)

F12::ExitApp


; Gets called when mouse moves or stops
; x and y are DELTA moves (Amount moved since last message), NOT coordinates.
MouseAcceleratorEvent(x := 0, y := 0, accelerationx := 1, accelerationy := 1.5){
    static MouseAcceleratorPaused
    If !(MouseAcceleratorPaused){
        MouseAcceleratorPaused:=true
        VarSetCapacity( MouseInput, 28, 0 )
        NumPut( x * accelerationx, MouseInput, 4, "Int" ) ; dx
        NumPut( y * accelerationy, MouseInput, 8, "Int" ) ; dy
        NumPut( 0x0001, MouseInput, 16, "UInt" ) ; MOUSEEVENTF_MOVE = 0x0001
        DllCall("SendInput", "UInt", 1, "UInt", &MouseInput, "Int", 28 )
        sleep,-1
        MouseAcceleratorPaused:=false
    }
}

; ================================== LIBRARY ========================================
; Instantiate this class and pass it a func name or a Function Object
; The specified function will be called with the delta move for the X and Y axes
; Normally, there is no windows message "mouse stopped", so one is simulated.
; After 10ms of no mouse movement, the callback is called with 0 for X and Y
; https://autohotkey.com/boards/viewtopic.php?f=19&t=10159
Class MouseAccelerator {
    __New(accelerationx:=2, accelerationy:=2, callback:="MouseAcceleratorEvent"){
        static DevSize := 8 + A_PtrSize
        static RIDEV_INPUTSINK := 0x00000100

        this.TimeoutFn := this.TimeoutFunc.Bind(this)

        this.Callback := callback
        this.Accelerationx := accelerationx
        this.Accelerationy := accelerationy
        ; Register mouse for WM_INPUT messages.
        VarSetCapacity(RAWINPUTDEVICE, DevSize)
        NumPut(1, RAWINPUTDEVICE, 0, "UShort")
        NumPut(2, RAWINPUTDEVICE, 2, "UShort")
        NumPut(RIDEV_INPUTSINK, RAWINPUTDEVICE, 4, "Uint")
        ; WM_INPUT needs a hwnd to route to, so get the hwnd of the AHK Gui.
        ; It doesn't matter if the GUI is showing, it still exists
        Gui +hwndhwnd
        NumPut(hwnd, RAWINPUTDEVICE, 8, "Uint")

        this.RAWINPUTDEVICE := RAWINPUTDEVICE
        DllCall("RegisterRawInputDevices", "Ptr", &RAWINPUTDEVICE, "UInt", 1, "UInt", DevSize )
        fn := this.MouseMoved.Bind(this)
        OnMessage(0x00FF, fn)
    }

    __Delete(){
        static RIDEV_REMOVE := 0x00000001
        static DevSize := 8 + A_PtrSize
        RAWINPUTDEVICE := this.RAWINPUTDEVICE
        NumPut(RIDEV_REMOVE, RAWINPUTDEVICE, 4, "Uint")
        DllCall("RegisterRawInputDevices", "Ptr", &RAWINPUTDEVICE, "UInt", 1, "UInt", DevSize )
    }

    ; Called when the mouse moved.
    ; Messages tend to contain small (+/- 1) movements, and happen frequently (~20ms)
    MouseMoved(wParam, lParam){
        ; RawInput statics
        static DeviceSize := 2 * A_PtrSize, iSize := 0, sz := 0, offsets := {x: (20+A_PtrSize*2), y: (24+A_PtrSize*2)}, uRawInput

        static axes := {x: 1, y: 2}

        ; Find size of rawinput data - only needs to be run the first time.
        if (!iSize){
            r := DllCall("GetRawInputData", "UInt", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", iSize, "UInt", 8 + (A_PtrSize * 2))
            VarSetCapacity(uRawInput, iSize)
        }
        sz := iSize ; param gets overwritten with # of bytes output, so preserve iSize
        ; Get RawInput data
        r := DllCall("GetRawInputData", "UInt", lParam, "UInt", 0x10000003, "Ptr", &uRawInput, "UInt*", sz, "UInt", 8 + (A_PtrSize * 2))

        x := NumGet(&uRawInput, offsets.x, "Int")
        y := NumGet(&uRawInput, offsets.y, "Int")

        this.Callback.(x, y, this.Accelerationx, this.Accelerationy)

        ; There is no message for "Stopped", so simulate one
        fn := this.TimeoutFn
        SetTimer, % fn, -10
    }

    TimeoutFunc(){
        this.Callback.(0, 0)
    }

}