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
unit EmsMem;

interface
	const
		EMS_MEM_CONVENTIONAL = 0;
		EMS_MEM_EXPANDED = 1;
	type
		EmsPointer = record
			PType: byte;
			Handle: word;
			Offset: word;
			Segment: word;
		end;
	var
		EmsError: byte;
	procedure EmsMove(length: word; source, dest: EmsPointer);
	procedure EmsMoveFrom(length: word; source: EmsPointer; dest: pointer);
	procedure EmsMoveTo(length: word; source: pointer; dest: EmsPointer);
	procedure EmsAllocate(var p: EmsPointer; length: word);
	procedure EmsFree(var p: EmsPointer; length: word);
	function EmsPagesAvail: word;
	function EmsAvailable: boolean;
	procedure EmsForceDisable;

implementation
uses Crt, Dos;

const
	EMS_PAGE_SIZE = 16384;
	MIN_EMS_VERSION = $40;
type
	HeapErrorFunc = function(size: word): integer;
	EmsCopyData = record
		Length: longint;
		Source: EmsPointer;
		Dest: EmsPointer;
	end;
var
	EmsVersion: byte;

{$F+}

function EmsHeapErrorHandler(size: word): integer;
	begin
		EmsError := $88;
		EmsHeapErrorHandler := 1; { prevent runtime error }
	end;

function EmsDefHeapErrorHandler(size: word): integer;
	begin
		EmsDefHeapErrorHandler := 0; { crash! }
	end;

{$F-}

procedure EmsMove(length: word; source, dest: EmsPointer);
	var
		copyData: EmsCopyData;
		regs: Registers;
	begin
		if (source.PType = EMS_MEM_CONVENTIONAL) and (dest.PType = EMS_MEM_CONVENTIONAL) then begin
			Move(Ptr(source.Segment, source.Offset)^, Ptr(dest.Segment, dest.Offset)^, length);
			EmsError := $00;
			exit;
		end;

		if EMSVersion < MIN_EMS_VERSION then begin
			EmsError := $80;
			exit;
		end;

		copyData.Length := length;
		copyData.Source := source;
		copyData.Dest := dest;

		if copyData.Source.PType = EMS_MEM_CONVENTIONAL then
			copyData.Source.Handle := 0;
		if copyData.Dest.PType = EMS_MEM_CONVENTIONAL then
			copyData.Dest.Handle := 0;

		regs.AX := $5700; { move }
		regs.DS := Seg(copyData);
		regs.SI := Ofs(copyData);
		Intr($67, regs);

		EmsError := regs.AH;
	end;

procedure EmsMoveFrom(length: word; source: EmsPointer; dest: pointer);
	var
		destEms: EmsPointer;
	begin
		destEms.PType := EMS_MEM_CONVENTIONAL;
		destEms.Segment := Seg(dest^);
		destEms.Offset := Ofs(dest^);
		EmsMove(length, source, destEms);
	end;

procedure EmsMoveTo(length: word; source: pointer; dest: EmsPointer);
	var
		srcEms: EmsPointer;
	begin
		srcEms.PType := EMS_MEM_CONVENTIONAL;
		srcEms.Segment := Seg(source^);
		srcEms.Offset := Ofs(source^);
		EmsMove(length, srcEms, dest);
	end;

procedure EmsAllocate(var p: EmsPointer; length: word);
	var
		convPtr: pointer;
		regs: Registers;
	begin
		if EmsVersion >= MIN_EMS_VERSION then begin
			regs.AH := $43;
			regs.BX := (length + EMS_PAGE_SIZE - 1) div EMS_PAGE_SIZE;
			Intr($67, regs);

			EmsError := regs.AH;
			if EmsError = $00 then begin
				p.PType := EMS_MEM_EXPANDED;
				p.Handle := regs.DX;
				p.Segment := 0;
				p.Offset := 0;

				exit;
			end;
		end;

		{ no EMS - try allocating conventional pointer }
		HeapError := @EmsHeapErrorHandler;
		EmsError := $00;

		GetMem(convPtr, length);
		if EmsError = $00 then begin
			p.PType := EMS_MEM_CONVENTIONAL;
			p.Segment := Seg(convPtr^);
			p.Offset := Ofs(convPtr^);
		end;

		HeapError := @EmsDefHeapErrorHandler;
	end;

procedure EmsFree(var p: EmsPointer; length: word);
	var
		regs: Registers;
	begin
		if p.PType = EMS_MEM_EXPANDED then begin
			regs.AH := $45;
			regs.DX := p.Handle;
			Intr($67, regs);

			EmsError := regs.AH;
			exit;
		end else begin
			HeapError := @EmsHeapErrorHandler;
			EmsError := $00;

			FreeMem(Ptr(p.Segment, p.Offset), length);

			HeapError := @EmsDefHeapErrorHandler;
		end;
	end;

function EmsPagesAvail: word;
	var
		regs: Registers;
	begin
		if EmsVersion < MIN_EMS_VERSION then begin
			EmsPagesAvail := 0;
			exit;
		end;

		regs.AH := $42;
		regs.BX := 0;
		Intr($67, regs);

		EmsPagesAvail := regs.BX;
	end;

function EmsAvailable: boolean;
	begin
		EmsAvailable := (EmsVersion >= MIN_EMS_VERSION);
	end;

procedure EmsForceDisable;
	begin
		EmsVersion := $00;
	end;

procedure EmsInit;
	var
		regs: Registers;
	begin
		regs.AH := $46;
		Intr($67, regs);

		if regs.AH = $00 then
			EmsVersion := regs.AL
		else
			EmsVersion := $00;
	end;

begin
	EmsInit;
	HeapError := @EmsDefHeapErrorHandler;
end.
