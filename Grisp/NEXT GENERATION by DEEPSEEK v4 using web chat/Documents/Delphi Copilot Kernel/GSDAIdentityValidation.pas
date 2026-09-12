unit GSDAIdentityValidation;

interface

uses
  System.SysUtils,
  System.JSON,
  GSDAIdentity,
  GSDACanonicalJson;

type
  // Validation result
  TIdentityValidationResult = record
    Valid: Boolean;
    Reason: string;
  end;

  // Validator
  TGSDAIdentityValidator = class
  private
    class function ValidateSemanticJson(const Obj: TJSONObject): TIdentityValidationResult; static;
    class function ContainsExecutionFields(const Obj: TJSONObject): Boolean; static;
    class function ContainsSemanticFields(const Obj: TJSONObject): Boolean; static;
  public
    // SEMANTIC IDENTITY VALIDATION
    class function ValidateSemanticId(Id: TSemanticIdentity): TIdentityValidationResult; static;

    // EXECUTION IDENTITY VALIDATION
    class function ValidateExecutionId(Id: TExecutionIdentity): TIdentityValidationResult; static;

    // COORDINATOR IDENTITY VALIDATION
    class function ValidateCoordinatorId(Id: TCoordinatorIdentity): TIdentityValidationResult; static;

    // DERIVED EXECUTION IDENTITY VALIDATION
    class function ValidateDerivedId(Id: TDerivedExecutionIdentity;
                                     LastSequence: Int64): TIdentityValidationResult; static;

    // COLLISION DETECTION
    class function DetectCollision(const IdA, IdB: string): TIdentityValidationResult; static;
  end;

implementation

uses
  System.Hash;

{ Helpers }

class function TGSDAIdentityValidator.ContainsExecutionFields(const Obj: TJSONObject): Boolean;
begin
  Result :=
    Obj.GetValue('run_id') <> nil or
    Obj.GetValue('peer_id') <> nil or
    Obj.GetValue('round_id') <> nil or
    Obj.GetValue('logical_sequence') <> nil;
end;

class function TGSDAIdentityValidator.ContainsSemanticFields(const Obj: TJSONObject): Boolean;
begin
  Result :=
    Obj.GetValue('content') <> nil or
    Obj.GetValue('semantic_projection') <> nil;
end;

class function TGSDAIdentityValidator.ValidateSemanticJson(const Obj: TJSONObject): TIdentityValidationResult;
begin
  if ContainsExecutionFields(Obj) then
  begin
    Result.Valid := False;
    Result.Reason := 'Semantic identity contains execution fields';
    Exit;
  end;

  Result.Valid := True;
  Result.Reason := '';
end;

{ SEMANTIC IDENTITY VALIDATION }

class function TGSDAIdentityValidator.ValidateSemanticId(Id: TSemanticIdentity): TIdentityValidationResult;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('schema', Id.Schema);
    Obj.AddPair('content', Id.Content.Clone as TJSONObject);

    Result := ValidateSemanticJson(Obj);
  finally
    Obj.Free;
  end;
end;

{ EXECUTION IDENTITY VALIDATION }

class function TGSDAIdentityValidator.ValidateExecutionId(Id: TExecutionIdentity): TIdentityValidationResult;
begin
  if Id.RunID = '' then
  begin
    Result.Valid := False;
    Result.Reason := 'Execution identity missing run_id';
    Exit;
  end;

  if Id.PeerID = '' then
  begin
    Result.Valid := False;
    Result.Reason := 'Execution identity missing peer_id';
    Exit;
  end;

  if Id.RoundID = '' then
  begin
    Result.Valid := False;
    Result.Reason := 'Execution identity missing round_id';
    Exit;
  end;

  Result.Valid := True;
  Result.Reason := '';
end;

{ COORDINATOR IDENTITY VALIDATION }

class function TGSDAIdentityValidator.ValidateCoordinatorId(Id: TCoordinatorIdentity): TIdentityValidationResult;
begin
  if not Id.Value.StartsWith('run:') then
  begin
    Result.Valid := False;
    Result.Reason := 'Coordinator identity must start with run:';
    Exit;
  end;

  if Pos('{', Id.Value) = 0 then
  begin
    Result.Valid := False;
    Result.Reason := 'Coordinator identity must contain a GUID';
    Exit;
  end;

  Result.Valid := True;
  Result.Reason := '';
end;

{ DERIVED EXECUTION IDENTITY VALIDATION }

class function TGSDAIdentityValidator.ValidateDerivedId(Id: TDerivedExecutionIdentity;
                                                        LastSequence: Int64): TIdentityValidationResult;
begin
  if Id.RoundID = '' then
  begin
    Result.Valid := False;
    Result.Reason := 'Derived identity missing round_id';
    Exit;
  end;

  if Id.LogicalSequence <= LastSequence then
  begin
    Result.Valid := False;
    Result.Reason := Format(
      'Derived identity logical_sequence %d is not monotonic (last=%d)',
      [Id.LogicalSequence, LastSequence]
    );
    Exit;
  end;

  Result.Valid := True;
  Result.Reason := '';
end;

{ COLLISION DETECTION }

class function TGSDAIdentityValidator.DetectCollision(const IdA, IdB: string): TIdentityValidationResult;
begin
  if IdA = IdB then
  begin
    Result.Valid := False;
    Result.Reason := 'Identity collision detected: two objects share the same identity';
    Exit;
  end;

  Result.Valid := True;
  Result.Reason := '';
end;

end.
