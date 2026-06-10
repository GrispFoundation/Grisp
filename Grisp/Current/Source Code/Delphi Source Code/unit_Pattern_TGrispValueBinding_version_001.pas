unit unit_Pattern_TGrispValueBinding_version_001;

interface

uses
  unit_Core_TGrispValueBase_version_001;  // Changed: use Base unit which contains TGrispValue

type
  TGrispValueBinding = record
    Name: string;
    Value: TGrispValue;
  end;

implementation

end.
