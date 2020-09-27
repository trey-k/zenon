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
			Data: array[1 .. 15] of word;
		end;
	var
		SoundEnabled: boolean;
		SoundBlockQueueing: boolean;
		SoundCurrentPriority: integer;
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
	procedure SoundQueue(priority: integer; pattern: string);
	procedure SoundClearQueue;
	function SoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	procedure SoundUninstall;
	function SoundParse(input: string): string;

implementation
uses Crt, Dos;

{$I SNDFREQ.INC}

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
			SoundTimeCheckCounter := SoundTimeCheckCounter - 1;
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
			SoundTimeCheckCounter := SoundTimeCheckCounter - 1;
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
					if (SoundBuffer[SoundBufferPos] >= #16) and (SoundBuffer[SoundBufferPos] < #112) then
						Sound(SoundFreqTable[Ord(SoundBuffer[SoundBufferPos])])
					else if (SoundBuffer[SoundBufferPos] >= #240) and (SoundBuffer[SoundBufferPos] < #250) then
						SoundPlayDrum(SoundDrumTable[Ord(SoundBuffer[SoundBufferPos]) - 240])
					else
						NoSound;
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
	procedure AdvanceInput;
		begin
			input := Copy(input, 2, Length(input) - 1);
		end;
	begin
		output := '';
		noteOctave := 3;
		noteDuration := 1;

		while Length(input) <> 0 do begin
			noteTone := -1;
			case UpCase(input[1]) of
				'T': begin
					noteDuration := 1;
					AdvanceInput;
				end;
				'S': begin
					noteDuration := 2;
					AdvanceInput;
				end;
				'I': begin
					noteDuration := 4;
					AdvanceInput;
				end;
				'Q': begin
					noteDuration := 8;
					AdvanceInput;
				end;
				'H': begin
					noteDuration := 16;
					AdvanceInput;
				end;
				'W': begin
					noteDuration := 32;
					AdvanceInput;
				end;
				'.': begin
					noteDuration := (noteDuration * 3) div 2;
					AdvanceInput;
				end;
				'3': begin
					noteDuration := noteDuration div 3;
					AdvanceInput;
				end;
				'+': begin
					if noteOctave < 6 then
						noteOctave := noteOctave + 1;
					AdvanceInput;
				end;
				'-': begin
					if noteOctave > 1 then
						noteOctave := noteOctave - 1;
					AdvanceInput;
				end;
				'A'..'G': begin
					case UpCase(input[1]) of
						'C': begin
							noteTone := 0;
							AdvanceInput;
						end;
						'D': begin
							noteTone := 2;
							AdvanceInput;
						end;
						'E': begin
							noteTone := 4;
							AdvanceInput;
						end;
						'F': begin
							noteTone := 5;
							AdvanceInput;
						end;
						'G': begin
							noteTone := 7;
							AdvanceInput;
						end;
						'A': begin
							noteTone := 9;
							AdvanceInput;
						end;
						'B': begin
							noteTone := 11;
							AdvanceInput;
						end;
					end;

					case UpCase(input[1]) of
						'!': begin
							noteTone := noteTone - 1;
							AdvanceInput;
						end;
						'#': begin
							noteTone := noteTone + 1;
							AdvanceInput;
						end;
					end;

					output := output + Chr(noteOctave * $10 + noteTone) + Chr(noteDuration);
				end;
				'X': begin
					output := output + #0 + Chr(noteDuration);
					AdvanceInput;
				end;
				'0'..'9': begin
					output := output + Chr(Ord(input[1]) + $F0 - Ord('0')) + Chr(noteDuration);
					AdvanceInput;
				end;
			else AdvanceInput end;
		end;
		SoundParse := output;
	end;

begin
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
