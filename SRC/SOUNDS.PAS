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

unit Sounds;

interface
	type
		TDrumData = record
			Len: integer;
			Data: array[1 .. 255] of word;
		end;
	var
		SoundEnabled: boolean;
		SoundBlockQueueing: boolean;
		SoundCurrentPriority: integer;
		SoundFreqTable: array[1 .. 255] of word;
		SoundDurationMultiplier: byte;
		SoundDurationCounter: byte;
		SoundBuffer: string;
		SoundNewVector: pointer;
		SoundOldVector: pointer;
		SoundBufferPos: integer;
		SoundIsPlaying: boolean;
		SoundTimeCheckCounter: integer;
		UseSystemTimeForElapsed: boolean;
		TimerTicks: word;
		SoundTimeCheckHsec: integer;
		SoundDrumTable: array[0 .. 9] of TDrumData;
	procedure SoundQueue(priority: integer; pattern: string);
	procedure SoundClearQueue;
	function SoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	procedure SoundUninstall;
	function SoundParse(input: string): string;

implementation
uses Crt, Dos;

procedure SoundQueue(priority: integer; pattern: string);
	begin
		if not SoundBlockQueueing and
			(not SoundIsPlaying or (((priority >= SoundCurrentPriority) and (SoundCurrentPriority <> -1)) or (priority = -1))) then
		begin
			if (priority >= 0) or not SoundIsPlaying then begin
				SoundCurrentPriority := priority;
				SoundBuffer := pattern;
				SoundBufferPos := 1;
				SoundDurationCounter := 1;
			end else begin
				SoundBuffer := Copy(SoundBuffer, SoundBufferPos, Length(SoundBuffer) - SoundBufferPos + 1);
				SoundBufferPos := 1;
				if (Length(SoundBuffer) + Length(pattern)) < 255 then begin
					SoundBuffer := SoundBuffer + pattern;
				end;
			end;
			SoundIsPlaying := true;
		end;
	end;

procedure SoundClearQueue;
	begin
		SoundBuffer := '';
		SoundIsPlaying := false;
		NoSound;
	end;

procedure SoundInitFreqTable;
	var
		octave, note: integer;
		freqC1, noteStep, noteBase, ln2: real;
	begin
		freqC1 := 32.0;
		ln2 := Ln(2.0);
		noteStep := Exp(ln2 / 12.0);
		for octave := 1 to 15 do begin
			noteBase := Exp(octave * ln2) * freqC1;
			for note := 0 to 11 do begin
				SoundFreqTable[octave * 16 + note] := Trunc(noteBase);
				noteBase := noteBase * noteStep;
			end;
		end;
	end;

procedure SoundInitDrumTable;
	var
		i: integer;
	begin
		SoundDrumTable[0].Len := 1;
		SoundDrumTable[0].Data[1] := 3200;
		for i := 1 to 9 do
			SoundDrumTable[i].Len := 14;
		for i := 1 to 14 do
			SoundDrumTable[1].Data[i] := i * 100 + 1000;
		for i := 1 to 16 do
			SoundDrumTable[2].Data[i] := (i mod 2) * 1600 + 1600 + (i mod 4) * 1600;
		for i := 1 to 14 do
			SoundDrumTable[4].Data[i] := Random(5000) + 500;
		for i := 1 to 8 do begin
			SoundDrumTable[5].Data[i * 2 - 1] := 1600;
			SoundDrumTable[5].Data[i * 2] := Random(1600) + 800;
		end;
		for i := 1 to 14 do
			SoundDrumTable[6].Data[i] := ((i mod 2) * 880) + 880 + ((i mod 3) * 440);
		for i := 1 to 14 do
			SoundDrumTable[7].Data[i] := 700 - (i * 12);
		for i := 1 to 14 do
			SoundDrumTable[8].Data[i] := (i * 20 + 1200) - Random(i * 40);
		for i := 1 to 14 do
			SoundDrumTable[9].Data[i] := Random(440) + 220;
	end;

procedure SoundPlayDrum(var drum: TDrumData);
	var
		i: integer;
	begin
		for i := 1 to drum.Len do begin
			Sound(drum.Data[i]);
			Delay(1);
		end;
		NoSound;
	end;

procedure SoundCheckTimeIntr;
	var
		hour, minute, sec, hSec: word;
	begin
		GetTime(hour, minute, sec, hSec);
		if (SoundTimeCheckHsec <> 0) and (Integer(hSec) <> SoundTimeCheckHsec) then begin
			SoundTimeCheckCounter := 0;
			UseSystemTimeForElapsed := true;
		end;
		SoundTimeCheckHsec := Integer(hSec);
	end;

function SoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	var
		hour, minute, sec, hSec: word;
		hSecsDiff: word;
		hSecsTotal: integer;
	begin
		if (SoundTimeCheckCounter > 0) and ((SoundTimeCheckCounter mod 2) = 1) then begin
			Dec(SoundTimeCheckCounter);
			SoundCheckTimeIntr;
		end;

		if UseSystemTimeForElapsed then begin
			GetTime(hour, minute, sec, hSec);
			hSecsTotal := sec * 100 + hSec;
			hSecsDiff := Word((hSecsTotal - counter) + 6000) mod 6000;
		end else begin
			hSecsTotal := TimerTicks * 6;
			hSecsDiff := hSecsTotal - counter;
		end;

		if hSecsDiff >= duration then begin
			SoundHasTimeElapsed := true;
			counter := hSecsTotal;
		end else begin
			SoundHasTimeElapsed := false;
		end;
	end;

procedure SoundTimerHandler;
	interrupt;
	begin
		Inc(TimerTicks);
		if (SoundTimeCheckCounter > 0) and ((SoundTimeCheckCounter mod 2) = 0) then begin
			Dec(SoundTimeCheckCounter);
		end;

		if not SoundEnabled then begin
			SoundIsPlaying := false;
			NoSound;
		end else if SoundIsPlaying then begin
			Dec(SoundDurationCounter);
			if SoundDurationCounter <= 0 then begin
				NoSound;
				if SoundBufferPos >= Length(SoundBuffer) then begin
					NoSound;
					SoundIsPlaying := false;
				end else begin
					if SoundBuffer[SoundBufferPos] = #0 then
						NoSound
					else if SoundBuffer[SoundBufferPos] < #240 then
						Sound(SoundFreqTable[Ord(SoundBuffer[SoundBufferPos])])
					else
						SoundPlayDrum(SoundDrumTable[Ord(SoundBuffer[SoundBufferPos]) - 240]);
					Inc(SoundBufferPos);

					SoundDurationCounter := SoundDurationMultiplier * Ord(SoundBuffer[SoundBufferPos]);
					Inc(SoundBufferPos);
				end;
			end;
		end;
	end;

procedure SoundUninstall;
	begin
		SetIntVec($1C, SoundOldVector);
	end;

function SoundParse(input: string): string;
	var
		noteOctave: integer;
		noteDuration: integer;
		output: string;
		noteTone: integer;
		inPos: byte;
	begin
		output := '';
		noteOctave := 3;
		noteDuration := 1;
		inPos := 1;

		while inPos <= Length(input) do begin
			noteTone := -1;
			case UpCase(input[inPos]) of
				'T': begin
					noteDuration := 1;
					Inc(inPos);
				end;
				'S': begin
					noteDuration := 2;
					Inc(inPos);
				end;
				'I': begin
					noteDuration := 4;
					Inc(inPos);
				end;
				'Q': begin
					noteDuration := 8;
					Inc(inPos);
				end;
				'H': begin
					noteDuration := 16;
					Inc(inPos);
				end;
				'W': begin
					noteDuration := 32;
					Inc(inPos);
				end;
				'.': begin
					noteDuration := (noteDuration * 3) div 2;
					Inc(inPos);
				end;
				'3': begin
					noteDuration := noteDuration div 3;
					Inc(inPos);
				end;
				'+': begin
					if noteOctave < 6 then
						Inc(noteOctave);
					Inc(inPos);
				end;
				'-': begin
					if noteOctave > 1 then
						Dec(noteOctave);
					Inc(inPos);
				end;
				'A'..'G': begin
					case UpCase(input[inPos]) of
						'C': begin
							noteTone := 0;
							Inc(inPos);
						end;
						'D': begin
							noteTone := 2;
							Inc(inPos);
						end;
						'E': begin
							noteTone := 4;
							Inc(inPos);
						end;
						'F': begin
							noteTone := 5;
							Inc(inPos);
						end;
						'G': begin
							noteTone := 7;
							Inc(inPos);
						end;
						'A': begin
							noteTone := 9;
							Inc(inPos);
						end;
						'B': begin
							noteTone := 11;
							Inc(inPos);
						end;
					end;

					if inPos <= Length(input) then case UpCase(input[inPos]) of
						'!': begin
							Dec(noteTone);
							Inc(inPos);
						end;
						'#': begin
							Inc(noteTone);
							Inc(inPos);
						end;
					end;

					output := output + Chr(noteOctave * $10 + noteTone) + Chr(noteDuration);
				end;
				'X': begin
					output := output + #0 + Chr(noteDuration);
					Inc(inPos);
				end;
				'0'..'9': begin
					output := output + Chr(Ord(input[inPos]) + $F0 - Ord('0')) + Chr(noteDuration);
					Inc(inPos);
				end;
			else Inc(inPos) end;
		end;
		SoundParse := output;
	end;

begin
	SoundInitFreqTable;
	SoundInitDrumTable;
	SoundTimeCheckCounter := 36;
	UseSystemTimeForElapsed := false;
	TimerTicks := 0;
	SoundTimeCheckHsec := 0;
	SoundEnabled := true;
	SoundBlockQueueing := false;
	SoundClearQueue;
	SoundDurationMultiplier := 1;
	SoundIsPlaying := false;
	TimerTicks := 0;
	SoundNewVector := @SoundTimerHandler;
	GetIntVec($1C, SoundOldVector);
	SetIntVec($1C, SoundNewVector);
end.
