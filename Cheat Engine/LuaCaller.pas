unit LuaCaller;
{
The luaCaller is a class which contains often defined Events and provides an
interface for gui objects to directly call the lua functions with proper parameters
and results
}

{$mode delphi}

interface

uses
  Classes, Controls, SysUtils, ceguicomponents, forms, lua, lualib, lauxlib,
  comctrls, StdCtrls, CEFuncProc, typinfo, Graphics;

type
  TLuaCaller=class
    private
      function canRun: boolean;

    public
      luaroutine: string;
      luaroutineindex: integer;
      owner: TPersistent;
      procedure NotifyEvent(sender: TObject);
      procedure SelectionChangeEvent(Sender: TObject; User: boolean);
      procedure MouseEvent(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
      procedure MouseMoveEvent(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      procedure MouseWheelUpDownEvent(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var h: Boolean);
      procedure KeyPressEvent(Sender: TObject; var Key: char);
      procedure LVCheckedItemEvent(Sender: TObject; Item: TListItem); //personal request to have this one added
      procedure CloseEvent(Sender: TObject; var CloseAction: TCloseAction);
      function MemoryRecordActivateEvent(sender: TObject; before, currentstate: boolean): boolean;
      procedure DisassemblerSelectionChangeEvent(sender: TObject; address, address2: ptruint);
      function DisassemblerExtraLineRender(sender: TObject; Address: ptruint; AboveInstruction: boolean; selected: boolean; var x: integer; var y: integer): TRasterImage;

      procedure ByteSelectEvent(sender: TObject; address: ptruint; address2: ptruint);
      procedure AddressChangeEvent(sender: TObject; address: ptruint);
      function AutoGuessEvent(address: ptruint; originalVariableType: TVariableType): TVariableType;
      procedure D3DClickEvent(renderobject: TObject; x,y: integer);
      function D3DKeyDownEvent(VirtualKey: dword; char: pchar): boolean;

      procedure pushFunction;


      constructor create;
      destructor destroy; override;
  end;

procedure CleanupLuaCall(event: TMethod);   //cleans up a luacaller class if it was assigned if it was set

procedure setMethodProperty(O: TObject; propertyname: string; method: TMethod);

function LuaCaller_NotifyEvent(L: PLua_state): integer; cdecl;
function LuaCaller_SelectionChangeEvent(L: PLua_state): integer; cdecl;
function LuaCaller_CloseEvent(L: PLua_state): integer; cdecl;
function LuaCaller_MouseEvent(L: PLua_state): integer; cdecl;
function LuaCaller_MouseMoveEvent(L: PLua_state): integer; cdecl;
function LuaCaller_MouseWheelUpDownEvent(L: PLua_state): integer; cdecl;
function LuaCaller_KeyPressEvent(L: PLua_state): integer; cdecl;
function LuaCaller_LVCheckedItemEvent(L: PLua_state): integer; cdecl;
function LuaCaller_MemoryRecordActivateEvent(L: PLua_state): integer; cdecl;
function LuaCaller_DisassemblerSelectionChangeEvent(L: PLua_state): integer; cdecl;
function LuaCaller_ByteSelectEvent(L: PLua_state): integer; cdecl;  //(sender: TObject; address: ptruint; address2: ptruint);
function LuaCaller_AddressChangeEvent(L: PLua_state): integer; cdecl;  //(sender: TObject; address: ptruint);

function LuaCaller_D3DClickEvent(L: PLua_state): integer; cdecl; //(renderobject: TObject; x,y: integer);
function LuaCaller_D3DKeyDownEvent(L: PLua_state): integer; cdecl; //(VirtualKey: dword; char: pchar): boolean;




procedure LuaCaller_pushMethodProperty(L: PLua_state; m: TMethod; typename: string);
procedure LuaCaller_setMethodProperty(L: PLua_state; c: TObject; prop: string; typename: string; luafunctiononstack: integer);  overload;
procedure LuaCaller_setMethodProperty(L: PLua_state; var m: TMethod; typename: string; luafunctiononstack: integer); overload;

function luacaller_getFunctionHeaderAndMethodForType(typeinfo: PTypeInfo; lc: pointer; name: string; header: tstrings) : Tmethod;

implementation

uses luahandler, MainUnit, MemoryRecordUnit, disassemblerviewunit, hexviewunit, d3dhookUnit, luaclass;

type
  TLuaCallData=class(tobject)
    GetMethodProp: lua_CFunction; //used when lua wants a function to a class method/property  (GetMethodProp)
    SetMethodProp: pointer; //used when we want to set a method property to a lua function (SetMethodProp)
    luafunctionheader: string;
  end;
var LuaCallList: Tstringlist;


function luacaller_getFunctionHeaderAndMethodForType(typeinfo: PTypeInfo; lc: pointer; name: string; header: tstrings) : Tmethod;
var i: integer;
  lcd: TLuaCallData;

begin
  result.Code:=nil;
  result.data:=nil;


  i:=LuaCallList.IndexOf(typeinfo.Name);
  if i<>-1 then
  begin
    lcd:=TLuaCallData(LuaCallList.Objects[i]);
    result.Code:=lcd.SetMethodProp;
    result.data:=lc;

    header.Text:=format(lcd.luafunctionheader, [name]);
  end;



end;

procedure LuaCaller_setMethodProperty(L: PLua_state; var m: TMethod; typename: string; luafunctiononstack: integer);
var
  lc: TLuaCaller;
  i,r: integer;

  newcode: pointer;
begin

  i:=LuaCallList.IndexOf(typename);
  if i=-1 then
    raise exception.create('This type of method:'+typename+' is not yet supported');

  newcode:=TLuaCallData(LuaCallList.Objects[i]).SetMethodProp;

  //proper type, let's clean it up
  CleanupLuaCall(m);
  lc:=nil;


  //create a TLuacaller for the given function
  if lua_isfunction(L, luafunctiononstack) then
  begin
    lua_pushvalue(L, luafunctiononstack);
    r:=luaL_ref(L,LUA_REGISTRYINDEX);

    lc:=TLuaCaller.create;
    lc.luaroutineIndex:=r;
  end
  else
  if lua_isstring(L, luafunctiononstack) then
  begin
    lc:=TLuaCaller.create;
    lc.luaroutine:=Lua_ToString(L, luafunctiononstack);
  end
  else
  if lua_isnil(L, luafunctiononstack) then
  begin
    m.code:=nil;
    m.data:=nil;
    exit;
  end;

  if lc<>nil then
  begin
    m.Data:=lc;
    m.code:=newcode;
  end;
end;

procedure LuaCaller_setMethodProperty(L: PLua_state; c: TObject; prop: string; typename: string; luafunctiononstack: integer);
//note: This only works on published methods
var m: tmethod;
begin
  m:=GetMethodProp(c, prop);
  LuaCaller_setMethodProperty(L, m, typename, luafunctiononstack);
  setMethodProp(c, prop, m);
end;

procedure luaCaller_pushMethodProperty(L: PLua_state; m: TMethod; typename: string);
var
  f: lua_CFunction;
  i: integer;
begin
  i:=LuaCallList.IndexOf(typename);
  if i=-1 then
    raise exception.create('This type of method:'+typename+' is not yet supported');

  f:=TLuaCallData(LuaCallList.Objects[i]).GetMethodProp;


  if m.data=nil then
  begin
    lua_pushnil(L);
    exit;
  end;

  if tobject(m.Data) is TLuaCaller then
    TLuaCaller(m.data).pushFunction
  else
  begin
    //not a lua function

    //this can (and often is) a class specific thing

    lua_pushlightuserdata(L, m.code);
    lua_pushlightuserdata(L, m.data);
    lua_pushcclosure(L, f,2);
  end;
end;

procedure CleanupLuaCall(event: TMethod);
begin
  if (event.code<>nil) and (event.data<>nil) and (TObject(event.data) is TLuaCaller) then
    TLuaCaller(event.data).free;
end;

procedure setMethodProperty(O: TObject; propertyname: string; method: TMethod);
var orig: TMethod;
begin
  orig:=GetMethodProp(o, propertyname);
  CleanupLuaCall(orig);
  SetMethodProp(O, propertyname, method);
end;

constructor TLuaCaller.create;
begin
  luaroutineindex:=-1;
end;

destructor TLuaCaller.destroy;
begin
  if luaroutineindex<>-1 then //deref
    luaL_unref(luavm, LUA_REGISTRYINDEX, luaroutineindex);
end;

function TLuaCaller.canRun: boolean;
var baseOwner: TComponent;
begin
  baseOwner:=Tcomponent(owner);
  if baseOwner<>nil then
  begin
    while (not (baseOwner is TCustomForm)) and (baseowner.Owner<>nil) do //as long as the current base is not a form and it still has a owner
      baseOwner:=baseowner.owner;
  end;

  result:=(baseowner=nil) or (not ((baseOwner is TCEform) and (TCEForm(baseowner).designsurface<>nil) and (TCEForm(baseowner).designsurface.active)));
end;

procedure TLuaCaller.pushFunction;
begin
  if luaroutineindex=-1 then //get the index of the given routine
    lua_getfield(LuaVM, LUA_GLOBALSINDEX, pchar(luaroutine))
  else
    lua_rawgeti(Luavm, LUA_REGISTRYINDEX, luaroutineindex)
end;

procedure TLuaCaller.SelectionChangeEvent(Sender: TObject; User: boolean);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushboolean(Luavm, User);

      lua_pcall(Luavm, 2,0,0); //procedure(sender)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.NotifyEvent(sender: TObject);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newclass(Luavm, sender);

      lua_pcall(Luavm, 1,0,0); //procedure(sender)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.CloseEvent(Sender: TObject; var CloseAction: TCloseAction);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);


      if lua_pcall(Luavm, 1,1,0)=0 then //procedure(sender)  lua_pcall returns 0 if success
      begin
        if lua_gettop(Luavm)>0 then
          CloseAction:=TCloseAction(lua_tointeger(LuaVM,-1));
      end
      else
        closeAction:=caHide; //not implemented by the user

      if mainform.mustclose then
        closeaction:=cahide;

    end
    else closeaction:=caHide;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

function TLuaCaller.MemoryRecordActivateEvent(sender: tobject; before, currentstate: boolean): boolean;
var oldstack: integer;
begin
  result:=true;
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushboolean(luavm, before);
      lua_pushboolean(luavm, currentstate);


      lua_pcall(Luavm, 3,1,0); //function(sender, before, currentstate):boolean

      if lua_gettop(Luavm)>0 then
        result:=lua_toboolean(LuaVM,-1);

    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

function TLuaCaller.DisassemblerExtraLineRender(sender: TObject; Address: ptruint; AboveInstruction: boolean; selected: boolean; var x: integer; var y: integer): TRasterImage;
var oldstack: integer;
begin
  result:=nil;
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canrun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushinteger(luavm, address);
      lua_pushboolean(luavm, AboveInstruction);
      lua_pushboolean(luavm, selected);

      lua_pcall(Luavm, 4,3,0); //function(sender, Address, AboveInstruction, Selected): RasterImage OPTIONAL, x OPTIONAL, y OPTIONAL

      result:=lua_ToCEUserData(luavm, 1);
      if lua_isnil(luavm, 2)=false then
        x:=lua_tointeger(luavm, 2);

      if lua_isnil(luavm, 3)=false then
        y:=lua_tointeger(luavm, 3);

    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.DisassemblerSelectionChangeEvent(sender: tobject; address, address2: ptruint);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushinteger(luavm, address);
      lua_pushinteger(luavm, address2);


      lua_pcall(Luavm, 3,0,0); //procedure(sender, address, address2)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.ByteSelectEvent(sender: TObject; address: ptruint; address2: ptruint);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushinteger(luavm, address);
      lua_pushinteger(luavm, address2);

      lua_pcall(Luavm, 3,0,0); //procedure(sender, address, address2)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

function TLuaCaller.D3DKeyDownEvent(VirtualKey: dword; char: pchar): boolean;
var oldstack: integer;
begin
  result:=true;
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      lua_pushinteger(luavm, VirtualKey);
      lua_pushstring(luavm, char);
      if lua_pcall(Luavm, 2,1,0)=0 then
        result:=lua_toboolean(luavm,-1);
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.D3DClickEvent(renderobject: TObject; x,y: integer);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(luavm, renderobject);
      lua_pushinteger(luavm, x);
      lua_pushinteger(luavm, y);
      lua_pcall(Luavm, 3,0,0)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.AddressChangeEvent(sender: TObject; address: ptruint);
var oldstack: integer;
begin
  Luacs.Enter;
  try
    oldstack:=lua_gettop(Luavm);

    if canRun then
    begin
      PushFunction;
      luaclass_newClass(Luavm, sender);
      lua_pushinteger(luavm, address);

      lua_pcall(Luavm, 2,0,0); //procedure(sender, address)
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;



function TLuaCaller.AutoGuessEvent(address: ptruint; originalVariableType: TVariableType): TVariableType;
var oldstack: integer;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);

    PushFunction;
    lua_pushinteger(luavm, address);
    lua_pushinteger(luavm, integer(originalVariableType));
    if lua_pcall(LuaVM, 2, 1, 0)=0 then         // lua_pcall returns 0 if success
      result:=TVariableType(lua_tointeger(LuaVM,-1))
    else
      result:=originalVariableType;




  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.MouseWheelUpDownEvent(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var h: Boolean);
var oldstack: integer;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);
    pushFunction;
    luaclass_newClass(luavm, sender);
    lua_pushinteger(luavm, MousePos.x);
    lua_pushinteger(luavm, MousePos.y);

    lua_pcall(LuaVM, 3, 0, 0);
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.MouseMoveEvent(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var oldstack: integer;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);
    pushFunction;
    luaclass_newClass(luavm, sender);
    lua_pushinteger(luavm, x);
    lua_pushinteger(luavm, y);

    lua_pcall(LuaVM, 3, 0, 0);
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.MouseEvent(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var oldstack: integer;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);
    pushFunction;
    luaclass_newClass(luavm, sender);
    lua_pushinteger(luavm, integer(Button));
    lua_pushinteger(luavm, x);
    lua_pushinteger(luavm, y);

    lua_pcall(LuaVM, 4, 0, 0);
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.KeyPressEvent(Sender: TObject; var Key: char);
var oldstack: integer;
  s: string;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);
    pushFunction;
    luaclass_newClass(luavm, sender);
    lua_pushstring(luavm, key);
    if lua_pcall(LuaVM, 2, 1, 0)=0 then  //lua_pcall returns 0 if success
    begin
      if lua_isstring(LuaVM, -1) then
      begin
        s:=lua_tostring(LuaVM,-1);
        if length(s)>0 then
          key:=s[1]
        else
          key:=#0; //invalid string
      end
      else
      if lua_isnumber(LuaVM, -1) then
        key:=chr(lua_tointeger(LuaVM, -1))
      else
        key:=#0; //invalid type returned
    end;
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end;
end;

procedure TLuaCaller.LVCheckedItemEvent(Sender: TObject; Item: TListItem);
var oldstack: integer;
begin
  Luacs.enter;
  try
    oldstack:=lua_gettop(Luavm);
    pushFunction;
    luaclass_newClass(luavm, sender);
    luaclass_newClass(luavm, item);
    lua_pcall(LuaVM, 2, 0, 0);
  finally
    lua_settop(Luavm, oldstack);
    luacs.leave;
  end
end;


//----------------------------Lua implementation-----------------------------
function LuaCaller_NotifyEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
begin
  result:=0;
  parameters:=lua_gettop(L);;

  if parameters=1 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));

    sender:=lua_toceuserdata(L, 1);
    lua_pop(L, lua_gettop(L));

    TNotifyEvent(m)(sender);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_SelectionChangeEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  user: boolean;
begin
  result:=0;
  parameters:=lua_gettop(L);;

  if parameters=1 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));

    sender:=lua_toceuserdata(L, 1);
    user:=lua_toboolean(L, 2);

    lua_pop(L, lua_gettop(L));

    TSelectionChangeEvent(m)(sender, user);
  end
  else
    lua_pop(L, lua_gettop(L));
end;


function LuaCaller_CloseEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  closeaction: TCloseAction;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=1 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    lua_pop(L, lua_gettop(L));

    TCloseEvent(m)(sender, closeaction);

    lua_pushinteger(L, integer(closeaction));
    result:=1;
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_MouseEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  button: TMouseButton;
  shift: TShiftState;
  x,y: integer;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=4 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    button:=TMouseButton(lua_tointeger(L, 2));

    x:=lua_tointeger(L, 3);
    y:=lua_tointeger(L, 4);

    lua_pop(L, lua_gettop(L));

    TMouseEvent(m)(sender, button, [], x,y);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_MouseMoveEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  x,y: integer;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=3 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    x:=lua_tointeger(L, 2);
    y:=lua_tointeger(L, 3);
    lua_pop(L, lua_gettop(L));

    TMouseMoveEvent(m)(sender, [],x,y);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_MouseWheelUpDownEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  p: TPoint;
  b: Boolean;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=3 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    p.x:=lua_tointeger(L, 2);
    p.y:=lua_tointeger(L, 3);
    lua_pop(L, lua_gettop(L));
    TMouseWheelUpDownEvent(m)(sender, [], p, b);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_KeyPressEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  key: char;
  s: string;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=2 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    s:=Lua_ToString(L,2);
    if length(s)>0 then
      key:=s[1]
    else
      key:=' ';

    lua_pop(L, lua_gettop(L));

    TKeyPressEvent(m)(sender, key);
    lua_pushstring(L, key);
    result:=1;
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_LVCheckedItemEvent(L: PLua_state): integer; cdecl;
var
  parameters: integer;
  m: TMethod;
  sender: TObject;
  item: TListItem;
begin
  result:=0;
  parameters:=lua_gettop(L);
  if parameters=1 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    lua_pop(L, lua_gettop(L));

    TLVCheckedItemEvent(m)(sender,item);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_MemoryRecordActivateEvent(L: PLua_state): integer; cdecl;
var
  m: TMethod;
  sender: TObject;
  before, currentstate: boolean;
  r: boolean;
begin
  result:=0;
  if lua_gettop(L)=3 then
  begin
    //(sender: TObject; before, currentstate: boolean):
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    before:=lua_toboolean(L, 2);
    currentstate:=lua_toboolean(L,3);
    lua_pop(L, lua_gettop(L));

    r:=TMemoryRecordActivateEvent(m)(sender,before, currentstate);
    lua_pushboolean(L, r);
    result:=1;
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_DisassemblerExtraLineRender(L: PLua_state): integer; cdecl;
//function(sender, Address, AboveInstruction, Selected): Bitmap OPTIONAL, x OPTIONAL, y OPTIONAL
var
  m: TMethod;
  sender: TObject;
  address: ptruint;
  AboveInstruction, selected: boolean;
  x,y: integer;
  r: TRasterimage;
begin
  result:=0;
  if lua_gettop(L)=4 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    address:=lua_tointeger(L, 2);
    AboveInstruction:=lua_toboolean(L, 3);
    selected:=lua_toboolean(L, 4);
    x:=-1000;
    y:=-1000;
    lua_pop(L, lua_gettop(L));
    r:=TDisassemblerExtraLineRender(m)(sender, address, AboveInstruction, selected, x, y);

    luaclass_newClass(L, r);
    if x=-1000 then
      lua_pushnil(L)
    else
      lua_pushinteger(L, x);

    if y=-1000 then
      lua_pushnil(L)
    else
      lua_pushinteger(L, y);

    result:=3;
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_DisassemblerSelectionChangeEvent(L: PLua_state): integer; cdecl;
//function(sender, address, address2)
var
  m: TMethod;
  sender: TObject;
  a,a2: ptruint;
begin
  result:=0;
  if lua_gettop(L)=3 then
  begin
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    a:=lua_tointeger(L, 2);
    a2:=lua_tointeger(L,3);
    lua_pop(L, lua_gettop(L));

    TDisassemblerSelectionChangeEvent(m)(sender,a, a2);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

//I could reuse LuaCaller_DisassemblerSelectionChangeEvent with   LuaCaller_ByteSelectEvent
function LuaCaller_ByteSelectEvent(L: PLua_state): integer; cdecl;  //(sender: TObject; address: ptruint; address2: ptruint);
var
  m: TMethod;
  sender: TObject;
  a,a2: ptruint;
begin
  result:=0;
  if lua_gettop(L)=3 then
  begin
    //(sender: TObject; before, currentstate: boolean):
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    a:=lua_tointeger(L, 2);
    a2:=lua_tointeger(L,3);
    lua_pop(L, lua_gettop(L));

    TByteSelectEvent(m)(sender,a, a2);
  end
  else
    lua_pop(L, lua_gettop(L));

end;

function LuaCaller_AddressChangeEvent(L: PLua_state): integer; cdecl;  //(sender: TObject; address: ptruint);
var
  m: TMethod;
  sender: TObject;
  a: ptruint;
begin
  result:=0;
  if lua_gettop(L)=3 then
  begin
    //(sender: TObject; before, currentstate: boolean):
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    sender:=lua_toceuserdata(L, 1);
    a:=lua_tointeger(L, 2);
    lua_pop(L, lua_gettop(L));

    TAddressChangeEvent(m)(sender,a);
  end
  else
    lua_pop(L, lua_gettop(L));

end;

function LuaCaller_D3DClickEvent(L: PLua_state): integer; cdecl;
var
  m: TMethod;
  renderobject: TObject;
  x,y: integer;
begin
  result:=0;
  if lua_gettop(L)=3 then
  begin
    //(renderobject: TObject; x,y: integer);
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    renderobject:=lua_toceuserdata(L, 1);
    x:=lua_tointeger(L, 2);
    y:=lua_tointeger(L, 3);
    lua_pop(L, lua_gettop(L));

    TD3DClickEvent(m)(renderobject,x,y);
  end
  else
    lua_pop(L, lua_gettop(L));
end;

function LuaCaller_D3DKeyDownEvent(L: PLua_state): integer; cdecl;
var
  m: TMethod;
  VirtualKey: dword;
  c: string;
  x,y: integer;
  r: boolean;
begin
  result:=0;
  if lua_gettop(L)=2 then
  begin
    //(VirtualKey: dword; char: pchar): boolean;
    m.code:=lua_touserdata(L, lua_upvalueindex(1));
    m.data:=lua_touserdata(L, lua_upvalueindex(2));
    virtualkey:=lua_tointeger(L, 1);
    c:=Lua_ToString(L,2);
    lua_pop(L, lua_gettop(L));

    if c<>'' then
    begin
      r:=TD3DKeyDownEvent(m)(VirtualKey,@c[1]);
      lua_pushboolean(L, r);
      result:=1;
    end;
  end
  else
    lua_pop(L, lua_gettop(L));
end;

procedure registerLuaCall(typename: string; getmethodprop: lua_CFunction; setmethodprop: pointer; luafunctionheader: string);
var t: TLuaCallData;
begin
  t:=TLuaCallData.Create;
  t.getmethodprop:=getmethodprop;
  t.setmethodprop:=setmethodprop;
  t.luafunctionheader:=luafunctionheader;
  LuaCallList.AddObject(typename, t);
end;

initialization
  LuaCallList:=TStringList.create;
  registerLuaCall('TNotifyEvent',  LuaCaller_NotifyEvent, pointer(TLuaCaller.NotifyEvent),'function %s(sender)'#13#10#13#10'end'#13#10);
  registerLuaCall('TSelectionChangeEvent', LuaCaller_SelectionChangeEvent, pointer(TLuaCaller.SelectionChangeEvent),'function %s(sender, user)'#13#10#13#10'end'#13#10);
  registerLuaCall('TCloseEvent', LuaCaller_CloseEvent, pointer(TLuaCaller.CloseEvent),'function %s(sender)'#13#10#13#10'return caHide --Possible options: caHide, caFree, caMinimize, caNone'#13#10'end'#13#10);
  registerLuaCall('TMouseEvent', LuaCaller_MouseEvent, pointer(TLuaCaller.MouseEvent),'function %s(sender, button, x, y)'#13#10#13#10'end'#13#10);
  registerLuaCall('TMouseMoveEvent', LuaCaller_MouseMoveEvent, pointer(TLuaCaller.MouseMoveEvent),'function %s(sender, x, y)'#13#10#13#10'end'#13#10);
  registerLuaCall('TMouseWheelUpDownEvent', LuaCaller_MouseWheelUpDownEvent, pointer(TLuaCaller.MouseWheelUpDownEvent),'function %s(sender, x, y)'#13#10#13#10'end'#13#10);
  registerLuaCall('TKeyPressEvent', LuaCaller_KeyPressEvent, pointer(TLuaCaller.KeyPressEvent),'function %s(sender, key)'#13#10#13#10'  return key'#13#10'end'#13#10);
  registerLuaCall('TLVCheckedItemEvent', LuaCaller_LVCheckedItemEvent, pointer(TLuaCaller.LVCheckedItemEvent),'function %s(sender, listitem)'#13#10#13#10'end'#13#10);
  registerLuaCall('TMemoryRecordActivateEvent', LuaCaller_MemoryRecordActivateEvent, pointer(TLuaCaller.MemoryRecordActivateEvent),'function %s(sender, before, current)'#13#10#13#10'end'#13#10);

  registerLuaCall('TDisassemblerSelectionChangeEvent', LuaCaller_DisassemblerSelectionChangeEvent, pointer(TLuaCaller.DisassemblerSelectionChangeEvent),'function %s(sender, address, address2)'#13#10#13#10'end'#13#10);
  registerLuaCall('TDisassemblerExtraLineRender', LuaCaller_DisassemblerExtraLineRender, pointer(TLuaCaller.DisassemblerExtraLineRender),'function %s(sender, Address, AboveInstruction, Selected)'#13#10#13#10'return nil,0,0'#13#10#13#10'end'#13#10);
  registerLuaCall('TByteSelectEvent', LuaCaller_ByteSelectEvent, pointer(TLuaCaller.ByteSelectEvent),'function %s(sender, address, address2)'#13#10#13#10'end'#13#10);
  registerLuaCall('TAddressChangeEvent', LuaCaller_AddressChangeEvent, pointer(TLuaCaller.AddressChangeEvent),'function %s(sender, address)'#13#10#13#10'end'#13#10);

  registerLuaCall('TD3DClickEvent', LuaCaller_D3DClickEvent, pointer(TLuaCaller.D3DClickEvent),'function %s(renderobject, x, y)'#13#10#13#10'end'#13#10);
  registerLuaCall('TD3DKeyDownEvent', LuaCaller_D3DKeyDownEvent, pointer(TLuaCaller.D3DKeyDownEvent),'function %s(virtualkeycode, char)'#13#10#13#10'  return false'#13#10'end'#13#10);
end.

