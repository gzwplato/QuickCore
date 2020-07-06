{ ***************************************************************************

  Copyright (c) 2016-2020 Kike P�rez

  Unit        : Quick.Core.Extensions.Authentication.Apikey
  Description : Core Extensions Authentication ApiKey
  Author      : Kike P�rez
  Version     : 1.0
  Created     : 10/03/2020
  Modified    : 09/06/2020

  This file is part of QuickCore: https://github.com/exilon/QuickCore

 ***************************************************************************

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

 *************************************************************************** }

unit Quick.Core.Extensions.Authentication.ApiKey;

{$i QuickCore.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Quick.Core.DependencyInjection,
  Quick.Options,
  Quick.Core.Mvc.Context,
  Quick.HttpServer.Request,
  Quick.HttpServer.Response,
  Quick.Core.Identity,
  Quick.Core.Identity.Store.Entity,
  Quick.Core.Security.Claims,
  Quick.Core.Security.Authentication;

type
  TApiKey = class;

  IApiKeyStore = interface
  ['{246E56E1-4E74-4980-A6D9-7F0764F4D462}']
    function IsValidKey(const aApiKey : string; out aValue : TApiKey) : Boolean;
  end;

  TApiKeyOptions = class(TOptions)
  private
    fUnAuthorizedErrorCode : Integer;
    fUnAuthorizedErrorMessage : string;
    fApiKeyStore : IApiKeyStore;
  public
    constructor Create; override;
    property ApiKeyStore : IApiKeyStore read fApiKeyStore write fApiKeyStore;
  published
    property UnAuthorizedErrorCode : Integer read fUnAuthorizedErrorCode write fUnAuthorizedErrorCode;
    property UnAuthorizedErrorMessage : string read fUnAuthorizedErrorMessage write fUnAuthorizedErrorMessage;
  end;

  TApiKey = class
  private
    fName : string;
    fRole : string;
    fKey : string;
    fExpiration : TDateTime;
    fActive : Boolean;
  public
    constructor Create(const aName, aRole, aKey: string; aExpiration: TDateTime = 0.0);
    destructor Destroy; override;
  published
    property Name : string read fName write fName;
    property Role : string read fRole write fRole;
    property Key : string read fKey write fKey;
    property Expiration : TDateTime read fExpiration write fExpiration;
    property Active : Boolean read fActive write fActive;
  end;

  TApiKeyMemoryStoreOptions = class(TApiKeyOptions)
  private
    fApiKeys : TObjectList<TApiKey>;
  public
    constructor Create; override;
    destructor Destroy; override;
    function AddApiKey(const aName, aKey : string; aExpiration : TDateTime = 0.0) : TApiKeyMemoryStoreOptions; overload;
    function AddApiKey(const aName, aRole, aKey : string; aExpiration : TDateTime = 0.0) : TApiKeyMemoryStoreOptions; overload;
  published
    property ApiKeys : TObjectList<TApiKey> read fApiKeys write fApiKeys;
  end;

  TMemoryApiKeyStore = class(TInterfacedObject,IApiKeyStore)
  private
    fOptions : TApiKeyMemoryStoreOptions;
    fApiKeys : TDictionary<string,TApiKey>;
    procedure GetKeysFromOptions;
  public
    constructor Create(aOptions : TApiKeyMemoryStoreOptions);
    destructor Destroy; override;
    function IsValidKey(const aApiKey : string; out aValue : TApiKey) : Boolean;
  end;

  TIdentityApiKeyStore = class(TInterfacedObject,IApiKeyStore)
  private
    fApiKeyPropertyName : string;
  public
    constructor Create(const aApiKeyPropertyName: string);
    function IsValidKey(const aApiKey : string; out aValue : TApiKey) : Boolean;
  end;

  TApiKeyAuthenticationHandler = class(TAuthenticationHandler<TApiKeyOptions>)
  private
    fApiKeyStore : IApiKeyStore;
  protected
    procedure DoInitialize; override;
  public
    function Authenticate : TAuthenticateResult; override;
  end;

  TSetApiKeyStore = record
  private
    fServiceCollection : TServiceCollection;
  public
    constructor Create(aServiceCollection : TServiceCollection);
    procedure UseMemoryStore(aConfigureOptions : TConfigureOptionsProc<TApiKeyMemoryStoreOptions>);
    procedure UseEntityStore(const aApiKeyPropertyName: string; aConfigureOptions : TConfigureOptionsProc<TApiKeyOptions> = nil);
  end;

  TApiKeyAuthenticationServiceExtension = class(TServiceCollectionExtension)
    class function AddApikey : TSetApiKeyStore;
  end;

  EApiKeyStore = class(Exception);

implementation

{ TApiKeyServiceExtension }

class function TApiKeyAuthenticationServiceExtension.AddApikey : TSetApiKeyStore;
var
  authOptions : TAuthenticationOptions;
begin
  //get AuthenticationOptions
  authOptions := ServiceCollection.Resolve<IOptions<TAuthenticationOptions>>.Value;
  ServiceCollection.AddTransient<TApiKeyAuthenticationHandler>;
  authOptions.AddScheme('ApiKey',TypeInfo(TApiKeyAuthenticationHandler));
  authOptions.DefaultAuthenticateScheme := 'ApiKey';
  Result.Create(ServiceCollection);
end;

{ TSetApiKeyStore }

constructor TSetApiKeyStore.Create(aServiceCollection: TServiceCollection);
begin
  fServiceCollection := aServiceCollection;
end;

procedure TSetApiKeyStore.UseEntityStore(const aApiKeyPropertyName: string; aConfigureOptions : TConfigureOptionsProc<TApiKeyOptions> = nil);
var
  options : TApiKeyOptions;
  indentityStore : IApiKeyStore;
begin
  indentityStore := TIdentityApiKeyStore.Create(aApiKeyPropertyName);
  options := TApiKeyOptions.Create;
  if Assigned(aConfigureOptions) then aConfigureOptions(options);
  options.Name := 'ApiKey';
  options.ApiKeyStore := indentityStore;
  fServiceCollection.Configure<TApiKeyOptions>(options);
  fServiceCollection.AddTransient<IAuthenticationHandler,TApiKeyAuthenticationHandler>;
end;

procedure TSetApiKeyStore.UseMemoryStore(aConfigureOptions : TConfigureOptionsProc<TApiKeyMemoryStoreOptions>);
var
  options : TApiKeyMemoryStoreOptions;
  memoryStore : IApiKeyStore;
begin
  options := TApiKeyMemoryStoreOptions.Create;
  aConfigureOptions(options);
  options.Name := 'ApiKey';
  fServiceCollection.Configure<TApiKeyOptions>(options);
  memoryStore := TMemoryApiKeyStore.Create(TApiKeyMemoryStoreOptions(options));
  options.ApiKeyStore := memoryStore;
  fServiceCollection.AddTransient<IAuthenticationHandler,TApiKeyAuthenticationHandler>;
end;


{ TMemoryApiKeyStore }

constructor TMemoryApiKeyStore.Create(aOptions : TApiKeyMemoryStoreOptions);
begin
  inherited Create;
  fOptions := aOptions;
  fApiKeys := TDictionary<string,TApiKey>.Create;
  GetKeysFromOptions;
end;

destructor TMemoryApiKeyStore.Destroy;
begin
  fOptions.Free;
  fApiKeys.Free;
  inherited;
end;

procedure TMemoryApiKeyStore.GetKeysFromOptions;
var
  apikey : TApiKey;
begin
  for apikey in fOptions.ApiKeys do
  begin
    if apikey.Active then fApiKeys.Add(apikey.Key,apikey);
  end;
end;

function TMemoryApiKeyStore.IsValidKey(const aApiKey : string; out aValue : TApiKey) : Boolean;
begin
  Result := fApiKeys.TryGetValue(aApiKey,aValue);
end;

{ TApiKeyAuthenticationHandler }

function TApiKeyAuthenticationHandler.Authenticate: TAuthenticateResult;
var
  reqApikey : string;
  apikey : TApiKey;
begin
  //try to get apikey from headers
  reqApikey := fRequest.Headers.GetValue('X-Api-Key');
  //try to get apikey from query
  if reqApikey.IsEmpty then reqApikey := fRequest.Query['ApiKey'].AsString;
  if reqApikey.IsEmpty then
  begin
    Result.NoResult;
    Exit;
  end;
  //check if valid
  if fApiKeyStore.IsValidKey(reqApikey,apikey) then
  begin
    var claimsidentity : TClaimsIdentity := TClaimsIdentity.Create;
    claimsidentity.AddClaim(TClaim.Create(TClaimTypes.NameIdentifier,Scheme.Name));
    claimsidentity.AddClaim(TClaim.Create(TClaimTypes.Name,apikey.Name));
    claimsidentity.AuthenticationType := Scheme.Name;
    if not apikey.Role.IsEmpty then claimsidentity.AddClaim(TClaim.Create(TClaimTypes.Role,apikey.Role));

    var claimPrincipal : TClaimsPrincipal := TClaimsPrincipal.Create;
    claimPrincipal.AddIdentity(claimsidentity);
    Result.Success(TAuthenticationTicket.Create(claimPrincipal,Scheme.Name));
  end
  else Result.Fail(nil);
end;

procedure TApiKeyAuthenticationHandler.DoInitialize;
begin
  if fOptions.ApiKeyStore = nil then raise EApiKeyStore.Create('Not defined Apikey store!');
  fApiKeyStore := fOptions.ApiKeyStore;
end;

{ TApiKeyMemoryStoreOptions }

constructor TApiKeyMemoryStoreOptions.Create;
begin
  inherited Create;
  fApiKeys := TObjectList<TApiKey>.Create(True);
end;

destructor TApiKeyMemoryStoreOptions.Destroy;
begin
  fApiKeys.Free;
  inherited;
end;

function TApiKeyMemoryStoreOptions.AddApiKey(const aName, aKey: string; aExpiration: TDateTime = 0.0): TApiKeyMemoryStoreOptions;
begin
  fApiKeys.Add(TApiKey.Create(aName,aKey,'',aExpiration));
end;

function TApiKeyMemoryStoreOptions.AddApiKey(const aName, aRole,aKey: string; aExpiration: TDateTime): TApiKeyMemoryStoreOptions;
begin
  fApiKeys.Add(TApiKey.Create(aName,aRole,aKey,aExpiration));
end;

{ TApiKey }

constructor TApiKey.Create(const aName, aRole, aKey: string; aExpiration: TDateTime = 0.0);
begin
  fName := aName;
  fRole := aRole;
  fKey := aKey;
  fExpiration := aExpiration;
  fActive := True;
end;

destructor TApiKey.Destroy;
begin

  inherited;
end;

{ TIdentityApiKeyStore }

constructor TIdentityApiKeyStore.Create(const aApiKeyPropertyName: string);
begin
  fApiKeyPropertyName := aApiKeyPropertyName;
end;

function TIdentityApiKeyStore.IsValidKey(const aApiKey : string; out aValue : TApiKey) : Boolean;
begin

end;

{ TApiKeyOptions }

constructor TApiKeyOptions.Create;
begin
  inherited;
  fUnAuthorizedErrorCode := 401;
  fUnAuthorizedErrorMessage := 'Not authenticated';
end;

end.
