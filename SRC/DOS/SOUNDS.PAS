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
		TimerTicks: word;
{$IFDEF ZETAEMU}
		ZetaDetected: boolean;
{$ENDIF}
	procedure AccurateDelayCalibrate;
	procedure AccurateDelay(ms: word);
	procedure SoundQueue(priority: integer; pattern: string);
	procedure SoundClearQueue;
	function SoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	procedure SoundUninstall;
	function SoundParse(input: string): string;

implementation
uses
{$IFDEF ZETAEMU}
ZetaSupp,
{$ENDIF}
Crt, Dos;

const
	DELAY_LOOP_MAX_ITERATIONS = $7FFFFFFF;
	SoundParseNoteTable: array['A' .. 'G'] of byte = (9, 11, 0, 2, 4, 5, 7);

{$I SNDFREQ.INC}

{$IFNDEF FPC}
var
	DelayLoopIterations: longint;

function AccurateDelayLoop(iterations: longint; var monitor: word): longint;
	begin
		inline(
			$8B/$BE/monitor/ { MOV DI, SS:[monitor] }
			$8B/$86/monitor+2/ { MOV AX, SS:[monitor+2] }
			$8E/$C0/ { MOV ES, AX }
			$8B/$86/iterations/ { MOV AX, SS:[iterations] }
			$8B/$96/iterations+2/ { MOV DX, SS:[iterations+2] }
			$8B/$1D/ { MOV BX, [ES:DI] }
		{ loop: }
			$90/$90/ { NOP x 2 }
			$83/$E8/$01/ { SUB AX, 1 }
			$83/$DA/$00/ { SBB DX, 0 }
			$72/$04/ { JC done }
			$3B/$1D/ { CMP BX, [ES:DI] }
			$74/$F2/ { JE loop }
		{ done: }
			$89/$86/AccurateDelayLoop/ { MOV AX, SS:[AccurateDelayLoop] }
			$89/$96/AccurateDelayLoop+2 { MOV DX, SS:[AccurateDelayLoop+2] }
		);
	end;

procedure AccurateDelayCalibrate;
	var
		iterations: longint;
		ticks: word;
	begin
		ticks := TimerTicks;
		repeat until TimerTicks <> ticks;
		iterations := AccurateDelayLoop(DELAY_LOOP_MAX_ITERATIONS, TimerTicks);
		DelayLoopIterations := (DELAY_LOOP_MAX_ITERATIONS - iterations) div 55;
	end;

procedure AccurateDelay(ms: word);
	var
		iterations: longint;
		unchanged: word;
	begin
{$IFDEF ZETAEMU}
		if ZetaDetected then begin
			ZetaDelay(ms);
			exit;
		end;
{$ENDIF}
		iterations := DelayLoopIterations * ms;
		if iterations <> 0 then
			iterations := AccurateDelayLoop(iterations, unchanged);
	end;
{$ELSE}
procedure AccurateDelayCalibrate;
	begin
		{ I'm not sure if Free Pascal lets you do this, though. }
	end;

procedure AccurateDelay(ms: word);
	begin
		{ Free Pascal contains properly calibrated delay logic. }
{$IFDEF ZETAEMU}
		if ZetaDetected then begin
			ZetaDelay(ms);
			exit;
		end;
{$ENDIF}
		Delay(ms);
	end;
{$ENDIF}

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
{$IFDEF ZETAEMU}
			if ZetaDetected then Delay(1) else
{$ENDIF}
			AccurateDelay(1);
		end;
		NoSound;
	end;

function SoundHasTimeElapsed(var counter: integer; duration: integer): boolean;
	var
		hSecsDiff: word;
		hSecsTotal: integer;
	begin
		hSecsTotal := (LongInt(TimerTicks) * 11) shr 1;
		hSecsDiff := hSecsTotal - counter;

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
					noteTone := SoundParseNoteTable[UpCase(input[inPos])];
					Inc(inPos);

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

					output := output + Chr((noteOctave shl 4) + noteTone) + Chr(noteDuration);
				end;
				'X': begin
					output := output + #0 + Chr(noteDuration);
					Inc(inPos);
				end;
{$IFNDEF FPC}
				'0'..'9': begin
{$ELSE}
				{ FPC does not like overlapping case labels. }
				'0'..'2','4'..'9': begin
{$ENDIF}
					output := output + Chr(Ord(input[inPos]) + $F0 - Ord('0')) + Chr(noteDuration);
					Inc(inPos);
				end;
			else Inc(inPos) end;
		end;
		SoundParse := output;
	end;

begin
	TimerTicks := 0;
	SoundEnabled := true;
	SoundBlockQueueing := false;
	SoundClearQueue;
	SoundDurationMultiplier := 1;
	SoundIsPlaying := false;
	TimerTicks := 0;
	SoundNewVector := @SoundTimerHandler;
	GetIntVec($1C, SoundOldVector);
	SetIntVec($1C, SoundNewVector);
{$IFNDEF FPC}
	DelayLoopIterations := 0;
	AccurateDelayCalibrate;
{$ENDIF}
{$IFDEF ZETAEMU}
	ZetaDetected := ZetaDetect;
{$ENDIF}
end.
