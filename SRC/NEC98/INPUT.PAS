{
	Copyright (c) 2020 Adrian Siekierka

	Based on a reconstruction of code from ZZT,
	Copyright 1991 Epic MegaGames, used with permission.

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
}

unit Input;

interface
	const
		KEY_BACKSPACE = #8;
		KEY_TAB = #9;
		KEY_ENTER = #13;
		KEY_ESCAPE = #27;
		KEY_F1 = #226; 
		KEY_F2 = #227;
		KEY_F3 = #228;
		KEY_F4 = #229;
		KEY_F5 = #230;
		KEY_F6 = #231;
		KEY_F7 = #232;
		KEY_F8 = #233;
		KEY_F9 = #234;
		KEY_F10 = #235;
		KEY_UP = #186;
		KEY_PAGE_UP = #182;
		KEY_LEFT = #187;
		KEY_RIGHT = #188;
		KEY_DOWN = #189;
		KEY_PAGE_DOWN = #183;
		KEY_INSERT = #184;
		KEY_DELETE = #185;
		KEY_HOME = #190;
		KEY_END = #191;
		{}
		KEY_CTRL_Z = #250;
		KEY_CTRL_C = #251;
		KEY_CTRL_X = #252;
		KEY_CTRL_V = #253;
		KEY_CTRL_Y = #254;
		KEY_ALT_P = #255; { TODO: not working }
	var
		InputDeltaX, InputDeltaY: integer;
		InputShiftPressed: boolean;
		InputShiftAccepted: boolean;
		InputJoystickEnabled: boolean;
		InputMouseEnabled: boolean;
		InputKeyPressed: char;
		InputMouseX, InputMouseY: integer;
		InputMouseActivationX, InputMouseActivationY: integer;
		InputMouseButtonX, InputMouseButtonY: integer;
		InputJoystickMoved: boolean;
		InputLastDeltaX, InputLastDeltaY: integer;
	procedure InputUpdate;
	procedure InputInitDevices;
	procedure InputReadWaitKey;
	function InputConfigure: boolean;

implementation
uses Dos, Keys, Sounds;

var
	InputKeyBuffer: string;

function KeyPressed: boolean;
	var
		regs: Registers;
	begin
		regs.AH := $01;
		Intr($18, regs);
{		KeyPressed := (regs.Flags and $02) <> 0; }
		KeyPressed := regs.BH <> 0;
	end;

function ReadKey: char;
	var
		regs: Registers;
	begin
		regs.AH := $00;
		Intr($18, regs);
		if (regs.AL <= $02) and (regs.AH <= $80) then
			ReadKey := Chr(regs.AH or $80)
		else
			ReadKey := Chr(regs.AL);
	end;

procedure InputUpdate;
	var
		regs: Registers;
	begin
		KeysUpdateModifiers;

		InputDeltaX := 0;
		InputDeltaY := 0;
		InputShiftPressed := false;
		InputJoystickMoved := false;
		while KeyPressed do begin
			InputKeyPressed := ReadKey;
			if (UpCase(InputKeyPressed) = 'Y') and KeysCtrlHeld then
				InputKeyPressed := KEY_CTRL_Y
			else if (UpCase(InputKeyPressed) = 'P') and KeysAltHeld then
				InputKeyPressed := KEY_ALT_P;
			InputKeyBuffer := InputKeyBuffer + InputKeyPressed;
		end;
		if Length(InputKeyBuffer) <> 0 then begin
			InputKeyPressed := InputKeyBuffer[1];
			if Length(InputKeyBuffer) = 1 then
				InputKeyBuffer := ''
			else
				InputKeyBuffer := Copy(InputKeyBuffer, Length(InputKeyBuffer) - 1, 1);

			case InputKeyPressed of
				KEY_UP, '8': begin
					InputDeltaX := 0;
					InputDeltaY := -1;
				end;
				KEY_LEFT, '4': begin
					InputDeltaX := -1;
					InputDeltaY := 0;
				end;
				KEY_RIGHT, '6': begin
					InputDeltaX := 1;
					InputDeltaY := 0;
				end;
				KEY_DOWN, '2': begin
					InputDeltaX := 0;
					InputDeltaY := 1;
				end;
			end;
		end else begin
			InputKeyPressed := #0;
		end;

		if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
			InputShiftPressed := KeysShiftHeld;
		end;

		{ TODO: Joystick, mouse? }

		if (InputDeltaX <> 0) or (InputDeltaY <> 0) then begin
			InputLastDeltaX := InputDeltaX;
			InputLastDeltaY := InputDeltaY;
		end;
	end;

procedure InputInitDevices;
	begin
		{ TODO }
	end;

function InputConfigure: boolean;
	begin
		{ TODO }
		InputConfigure := true;
	end;

procedure InputReadWaitKey;
	begin
		repeat
			InputUpdate
		until InputKeyPressed <> #0;
	end;

begin
	InputLastDeltaX := 0;
	InputLastDeltaY := 0;
	InputDeltaX := 0;
	InputDeltaY := 0;
	InputShiftPressed := false;
	InputShiftAccepted := false;
	InputMouseX := 0;
	InputMouseY := 0;
	InputMouseActivationX := 60;
	InputMouseActivationY := 60;
	InputMouseButtonX := 0;
	InputMouseButtonY := 0;
	InputKeyBuffer := '';
end.
