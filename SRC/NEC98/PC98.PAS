{
	Copyright (c) 2020 Adrian Siekierka

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
unit PC98;

interface
	const
		Black = 0;
		Blue = 1;
		Green = 2;
		Cyan = 3;
		Red = 4;
		Magenta = 5;
		Yellow = 6;
		White = 7;
	procedure Sound(hz: word);
	procedure NoSound;
	procedure ClrScr;

implementation
uses Dos, Sounds, PC98FONT;

procedure Sound(hz: word);
	var
		convHz: word;
	begin
		convHz := SoundFreqDivisor div hz;
		if not SpeakerActive then begin
			Port[$77] := $76;
			SpeakerActive := true;
		end;
		Port[$73] := Lo(convHz);
		Port[$73] := Hi(convHz);

		Port[$37] := $08;
		Port[$35] := Port[$35] and $F7;
	end;

procedure NoSound;
	begin
		Port[$35] := Port[$35] or $08;
		Port[$37] := $09;
		SpeakerActive := false;
	end;

procedure ClrScr;
	var
		regs: Registers;
	begin
		regs.AH := $16;
		regs.DX := $0020;
		Intr($18, regs);
	end;		

procedure LoadFontData;
	var
		chr: array[0 .. 33] of byte;
		cPtr: pointer;
		i, j: integer;
		regs: Registers;
	begin
		cPtr := Ptr(Seg(chr), Ofs(chr) + 2);
		for i := 0 to (PC98FONTSize shr 4) do begin
			for j := 0 to 15 do begin
				chr[(j shl 1) + 2] := PC98FONTData[(i shl 4) or j];
				chr[(j shl 1) + 3] := PC98FONTData[(i shl 4) or j];
			end;
			regs.AH := $1A;
			regs.BX := Seg(chr);
			regs.CX := Ofs(chr);
			regs.DX := ($7601 + ((i and $7E) shr 1)) + ((i and $01) shl 8);
			Intr($18, regs);
		end;
	end;

begin
	LoadFontData;
end.
