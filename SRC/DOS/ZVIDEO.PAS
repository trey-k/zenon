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

{$I-}
unit ZVideo;

interface
	type
		TVideoLine = string[80];
		TScreenCopyLine = string[160];
		TVideoWriteTextProc = procedure(x, y, color: byte; text: TVideoLine);
	const
		PORT_CGA_MODE = $03D8;
		PORT_CGA_PALETTE = $03D9;
	var
		VideoWriteText: TVideoWriteTextProc;
		VideoMonochrome: boolean;
		VideoColumns: integer;
		VideoTextSegment: word;
		VideoEGAInstalled: boolean;
		VideoMDAInstalled: boolean;
		VideoLastMode: word;
	function VideoConfigure: boolean;
	procedure VideoInstall(borderColor: integer);
	procedure VideoUninstall;
	procedure VideoShowCursor;
	procedure VideoHideCursor;
	procedure VideoSetBorderColor(value: integer);
	procedure VideoSetBlink(value: boolean);
	procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);

implementation
uses Crt, Dos;

{$F+}

{$IFNDEF FPC}
procedure VideoWriteTextCGA(x, y, color: byte; text: TVideoLine);
	begin
		inline(
			$8B/$06/VideoTextSegment/{ MOV AX, VideoTextSegment }
			$8E/$C0/             { MOV ES, AX }
			$8A/$86/y/           { MOV AL, byte ptr [BP + y] }
			$F6/$26/VideoColumns/{ MUL VideoColumns }
			$31/$C9/             { XOR CX, CX }
			$89/$CE/             { MOV SI, CX }
			$8A/$8E/x/           { MOV CL, byte ptr [BP + x] }
			$01/$C8/             { ADD AX, CX }
			$D1/$E0/             { SHL AX, 1 }
			$8B/$F8/             { MOV DI, AX }
			$8A/$BE/color/       { MOV BH, byte ptr [BP + color] }
			$8A/$8E/text/        { MOV CL, byte ptr [BP + text] }
			$BA/$03DA/           { MOV DX, 0x03DA }
			$22/$C9/             { AND CL, CL }
			$74/$1A/             { JZ finish }
			$FA/                 { CLI }
		{ next_char: }
			$46/                 { INC SI }
			$8A/$9A/text/        { MOV BL, byte ptr [BP + SI + text] }
		{ cga_snow: }
			$EC/                 { IN AL, DX }
			$A8/$08/             { TEST AL, 8 }
			$75/$09/             { JNZ write_char }
			$D0/$E8/             { SHR AL, 1 }
			$72/$F7/             { JC cga_snow }
		{ cga_snow2: }
			$EC/                 { IN AL, DX }
			$D0/$E8/             { SHR AL, 1 }
			$73/$FB/             { JNC cga_snow2 }
		{ write_char: }
			$89/$D8/             { MOV AX, BX }
			$AB/                 { STOSW }
			$E2/$E8/             { LOOP next_char }
			$FB                  { STI }
		{ finish: }
		);
	end;

procedure VideoWriteTextFast(x, y, color: byte; text: TVideoLine);
	begin
		inline(
			$8B/$06/VideoTextSegment/{ MOV AX, VideoTextSegment }
			$8E/$C0/             { MOV ES, AX }
			$8A/$86/y/           { MOV AL, byte ptr [BP + y] }
			$F6/$26/VideoColumns/{ MUL VideoColumns }
			$31/$C9/             { XOR CX, CX }
			$89/$CE/             { MOV SI, CX }
			$8A/$8E/x/           { MOV CL, byte ptr [BP + x] }
			$01/$C8/             { ADD AX, CX }
			$D1/$E0/             { SHL AX, 1 }
			$8B/$F8/             { MOV DI, AX }
			$8A/$A6/color/       { MOV AH, byte ptr [BP + color] }
			$8A/$8E/text/        { MOV CL, byte ptr [BP + text] }
			$22/$C9/             { AND CL, CL }
			$74/$0A/             { JZ finish }
			$FA/                 { CLI }
		{ next_char: }
			$46/                 { INC SI }
			$8A/$82/text/        { MOV AL, byte ptr [BP + SI + text] }
			$AB/                 { STOSW }
			$E2/$F8/             { LOOP next_char }
			$FB                  { STI }
		{ finish: }
		);
	end;
{$ELSE}
procedure VideoWriteTextCGA(x, y, color: byte; text: TVideoLine);
	assembler;
	label next_char;
	label cga_snow;
	label cga_snow2;
	label write_char;
	label finish;
	asm
		push es
		mov ax, VideoTextSegment
		mov es, ax
		mov al, y
		mul VideoColumns
		xor cx, cx
		mov cl, x
		add ax, cx
		shl ax, 1
		mov di, ax
		mov bh, color
		mov dx, 03DAh
		push ds
		lds si, [text]
		mov cl, [si]
		and cl, cl
		jz finish
		cli
	next_char:
		inc si
		mov bl, [si]
	cga_snow:
		in al, dx
		test al, 8
		jnz write_char
		shr al, 1
		jc cga_snow
	cga_snow2:
		in al, dx
		shr al, 1
		jnc cga_snow2
	write_char:
		mov ax, bx
		stosw
		loop next_char
		sti
	finish:
		pop ds
		pop es
	end ['ax', 'bx', 'cx', 'dx', 'si', 'di'];

procedure VideoWriteTextFast(x, y, color: byte; text: TVideoLine);
	assembler;
	label next_char;
	label finish;
	asm
		push es
		mov ax, VideoTextSegment
		mov es, ax
		mov al, y
		mul VideoColumns
		xor cx, cx
		mov cl, x
		add ax, cx
		shl ax, 1
		mov di, ax
		mov ah, color
		mov dx, 03DAh
		push ds
		lds si, [text]
		mov cl, [si]
		and cl, cl
		jz finish
		cli
	next_char:
		inc si
		mov al, [si]
		stosw
		loop next_char
		sti
	finish:
		pop ds
		pop es
	end ['ax', 'cx', 'dx', 'si', 'di'];
{$ENDIF}

{$F-}

function ColorToBW(color: byte): byte;
	begin
		{ FIX: Special handling of blinking solids }
		if (color and $80) = $80 then
			if ((color shr 4) and $07) = (color and $0F) then
				color := (color and $7F);

		if (color and $09) = $09 then
			color := (color and $F0) or $0F
		else if (color and $07) <> 0 then
			color := (color and $F0) or $07;

		if (color and $0F) = $00 then begin
			if (color and $70) = $00 then
				color := (color and $8F)
			else
				color := (color and $8F) or $70;
		end else if (color and $70) <> $70 then
			color := color and $8F;

		ColorToBW := color;
	end;

{$F+}

procedure VideoWriteTextCGABW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextCGA(x, y, ColorToBW(color), text);
	end;

procedure VideoWriteTextFastBW(x, y, color: byte; text: TVideoLine);
	begin
		VideoWriteTextFast(x, y, ColorToBW(color), text);
	end;

{$F-}

function VideoConfigure: boolean;
	var
		charTyped: Char;
	begin
		charTyped := ' ';
		if VideoLastMode = 7 then begin
			VideoWriteText := VideoWriteTextFastBW;
			VideoMonochrome := true;
		end else begin
			Writeln;
			Write('  Video mode:  C)olor,  M)onochrome?  ');
			repeat
				repeat until KeyPressed;
				charTyped := UpCase(ReadKey);
			until charTyped in [#27, 'C', 'M'];
			case charTyped of
				'C', #27: VideoMonochrome := false;
				'M': VideoMonochrome := true;
				{ #27: false if (VideoLastMode = 7);, checked above }
			end;
		end;
		VideoConfigure := charTyped <> #27;
	end;

procedure VideoInstall(borderColor: integer);
	var
		regs: Registers;
	begin
		regs.AH := $12;
		regs.BX := $FF10;
		Intr($10, regs);
		VideoEGAInstalled := regs.BH <> $FF;
		VideoMDAInstalled := VideoLastMode = 7;

		if VideoEGAInstalled then begin
			regs.AX := $1201;
			regs.BL := $30;
			Intr($10, regs);
		end;

		VideoColumns := 80;
		if VideoMonochrome then begin
			if VideoEGAInstalled or VideoMDAInstalled then
				VideoWriteText := VideoWriteTextFastBW
			else
				VideoWriteText := VideoWriteTextCGABW;

			if (VideoLastMode and $FFFC) = 0 {>= 0, <= 3} then begin
				TextMode(BW80);
			end else begin
				TextMode(7);
			end;
		end else begin
			if VideoEGAInstalled then
				VideoWriteText := VideoWriteTextFast
			else
				VideoWriteText := VideoWriteTextCGA;

			TextMode(CO80);
			TextBackground(borderColor);
			VideoSetBorderColor(borderColor);
		end;

		ClrScr;
		VideoHideCursor;
	end;

procedure VideoUninstall;
	var
		regs: Registers;
	begin
		if VideoEGAInstalled then begin
			regs.AX := $1201;
			regs.BL := $30;
			Intr($10, regs);
		end;

		TextBackground(0);
		VideoColumns := 80;
		TextMode(VideoLastMode);
		VideoSetBorderColor(0);
		ClrScr;
	end;

procedure VideoSetCursorShape(value: integer);
	var
		regs: Registers;
	begin
		regs.AH := $01;
		regs.CX := value;
		Intr($10, regs);
	end;

procedure VideoShowCursor;
	begin
		VideoSetCursorShape($0607);
	end;

procedure VideoHideCursor;
	begin
		VideoSetCursorShape($2000);
	end;

procedure VideoSetBorderColor(value: integer);
	begin
		Port[PORT_CGA_PALETTE] := value;
	end;

procedure VideoSetBlink(value: boolean);
	var
		regs: Registers;
	begin
		{ CGA route }
		if value then
			Port[PORT_CGA_MODE] := Port[PORT_CGA_MODE] or $20
		else
			Port[PORT_CGA_MODE] := Port[PORT_CGA_MODE] and $DF;
		{ EGA/VGA route }
		regs.AX := $1003;
		regs.BH := 0;
		regs.BL := Byte(value);
		Intr($10, regs);
	end;

procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	var
		offset: integer;
	begin
		offset := (y * VideoColumns + x) * 2;
		if toVideo then
			Move(data^, Ptr(VideoTextSegment, offset)^, chars * 2)
		else
			Move(Ptr(VideoTextSegment, offset)^, data^, chars * 2);
	end;


begin
	VideoColumns := 80;
	VideoWriteText := VideoWriteTextCGA;
	VideoLastMode := LastMode;
	if VideoLastMode = 7 then begin
		VideoTextSegment := $B000;
		VideoMonochrome := true;
	end else begin
		VideoTextSegment := $B800;
		VideoMonochrome := false;
	end;
end.
