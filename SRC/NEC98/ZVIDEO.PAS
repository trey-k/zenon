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
		TScreenCopyLine = string[200];
	var
		VideoEightColor: boolean;
		VideoMonochrome: boolean;
		VideoBlinkMask: byte;
	function VideoConfigure: boolean;
	procedure VideoWriteText(x, y, color: byte; text: TVideoLine);
	procedure VideoInstall(borderColor: integer);
	procedure VideoUninstall;
	procedure VideoShowCursor;
	procedure VideoHideCursor;
	procedure VideoSetBorderColor(value: integer);
	procedure VideoSetBlink(value: boolean);
	procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	procedure VideoInvert(x1, y1, x2, y2: integer);

implementation
uses Dos, PC98;

{$I VIDCONST.INC}
		
procedure VideoWriteText(x, y, color: byte; text: TVideoLine);
	var
		attr: word;
		i, offset: integer;
	begin
		offset := (y * 80 + x) * 2;
		if ((color and $70) shr 4) = (color and $0F) then begin
			{ Same color. }
			attr := ATTR_MAP[color and $70];
			for i := 1 to Length(text) do begin
				MemW[$A000:offset] := $0020;
				MemW[$A200:offset] := attr;
				Inc(offset, 2);
			end;
		end else begin
			attr := ATTR_MAP[color and $7F] or (((color and $80) shr 6) and VideoBlinkMask);
			for i := 1 to Length(text) do begin
				MemW[$A000:offset] := CP437_MAP[Ord(text[i])];
				MemW[$A200:offset] := attr;
				Inc(offset, 2);
			end;
		end;
	end;

function VideoConfigure: boolean;
	begin
		VideoConfigure := True;
	end;

procedure VideoInstall(borderColor: integer);
	var
		regs: Registers;
	begin
		{ TODO }
		ClrScr;
	end;

procedure VideoUninstall;
	var
		regs: Registers;
	begin
		{ TODO }
		ClrScr;
	end;

procedure VideoShowCursor;
	var
		regs: Registers;
	begin
		regs.AH := $11;
		Intr($18, regs);
	end;

procedure VideoHideCursor;
	var
		regs: Registers;
	begin
		regs.AH := $12;
		Intr($18, regs);
	end;

procedure VideoSetBorderColor(value: integer);
	begin
		{ TODO }
	end;

{ TODO: This doesn't update existing characters. }
procedure VideoSetBlink(value: boolean);
	begin
		if value then
			VideoBlinkMask := $FF
		else
			VideoBlinkMask := $00;
	end;

procedure VideoMove(x, y, chars: integer; data: pointer; toVideo: boolean);
	var
		offset: integer;
	begin
		offset := (y * 80 + x) * 2;
		if toVideo then begin
			Move(data^, Ptr($A000, offset)^, chars * 2);
			Move(Ptr(Seg(data^), Ofs(data^) + (chars * 2))^, Ptr($A200, offset)^, chars * 2);
		end else begin
			Move(Ptr($A000, offset)^, data^, chars * 2);
			Move(Ptr($A200, offset)^, Ptr(Seg(data^), Ofs(data^) + (chars * 2))^, chars * 2);
		end
	end;

procedure VideoInvert(x1, y1, x2, y2: integer);
	var
		ix, iy, offset: integer;
	begin
		if x2 < x1 then begin
			ix := x1;
			x1 := x2;
			x2 := ix;
		end;
		if y2 < y1 then begin
			ix := y1;
			y1 := y2;
			y2 := ix;
		end;
		for iy := y1 to y2 do begin
			offset := ((iy * 80) + x1) shl 1;
				for ix := x1 to x2 do begin
				MemW[$A200:offset] := MemW[$A200:offset] xor $04;
				Inc(offset, 2);
			end;
		end;
	end;
		
begin
	VideoEightColor := true;
	VideoMonochrome := false;
	VideoBlinkMask := $FF;

	SetCBreak(false);
end.
