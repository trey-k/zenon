{
	Copyright (c) 2021 Adrian Siekierka

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
{$V-}
unit DebugWnd;

interface
	procedure DebugShowElementMessage(msg: string; x, y: integer);

implementation
uses GameVars, Game, Sounds, TxtWind;

procedure DebugShowElementMessage(msg: string; x, y: integer);
var
	statId: integer;
	xStr, yStr, zStr: string[11];
	textWindow: TTextWindowState;
begin
	Str(x, xStr);
	Str(y, yStr);

	textWindow.Title := '[Debug] Element Error';
	TextWindowInitState(textWindow);
	TextWindowAppend(textWindow, '$' + msg);
	TextWindowAppend(textWindow, '');
	TextWindowAppend(textWindow, 'Position: ' + xStr + ', ' + yStr);

	Str(World.Info.CurrentBoard, xStr);
	TextWindowAppend(textWindow, 'Board: #' + xStr);

	Str(Board.Tiles[x][y].Element, xStr);
	TextWindowAppend(textWindow, 'Element: ' + ElementDefs[Board.Tiles[x][y].Element].Name + ' (' + xStr + ')');

	statId := GetStatIdAt(x, y);
	if statId >= 0 then begin
		with Board.Stats[statId] do begin
			Str(statId, xStr);
			TextWindowAppend(textWindow, 'Stat: #' + xStr);
			Str(StepX, xStr);
			Str(StepY, yStr);
			TextWindowAppend(textWindow, '- Step: ' + xStr + ', ' + yStr);
			Str(Cycle, xStr);
			TextWindowAppend(textWindow, '- Cycle: ' + xStr);
			Str(P1, xStr);
			Str(P2, yStr);
			Str(P3, zStr);
			TextWindowAppend(textWindow, '- Param: ' + xStr + ', ' + yStr + ', ' + zStr);
			Str(Follower, xStr);
			Str(Leader, yStr);
			TextWindowAppend(textWindow, '- Follower: ' + xStr + ', Leader: ' + yStr);
			if DataLen <> 0 then begin
				Str(DataPos, xStr);
				Str(DataLen, yStr);
				TextWindowAppend(textWindow, '- DataPos: ' + xStr + '/' + yStr);
			end;
		end;
	end;

	SoundQueue(5, #80#10);
	TextWindowDrawOpen(textWindow);
	TextWindowSelect(textWindow, false, false);
	TextWindowDrawClose(textWindow);
	TextWindowFree(textWindow);
end;

end.
