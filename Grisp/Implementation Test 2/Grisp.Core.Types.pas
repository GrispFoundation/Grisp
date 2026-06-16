unit Grisp.Core.Types;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TValueKind = (vkInt, vkFixed, vkBool, vkString, vkIdentifier, vkList, vkMap);

  TValue = record
    Kind: TValueKind;
    case Byte of
      0: (AsInt: Int64);
      1: (AsFixedRaw: Int64; FixedScale: Byte);   // scale 0..18, value = AsFixedRaw * 10^(-FixedScale)
      2: (AsBool: Boolean);
      3: (AsString: UTF8String);
      4: (AsIdType: UTF8String; AsIdSeq: Int64);
      5: (AsList: TArray<TValue>);
      6: (AsMap: TDictionary<UTF8String, TValue>);
  end;

  TNodeId = record
    TypeName: UTF8String;
    Seq: Int64;
  end;

  TEdgeId = record
    TypeName: UTF8String;
    Seq: Int64;
  end;

  TFieldMap = TDictionary<UTF8String, TValue>;
  TEdgeIdList = TArray<TEdgeId>;

  TNode = record
    Id: TNodeId;
    Fields: TFieldMap;
    OutEdges: TEdgeIdList;
    InEdges: TEdgeIdList;
  end;

  TEdge = record
    Id: TEdgeId;
    Src: TNodeId;
    Tgt: TNodeId;
    Fields: TFieldMap;
  end;

  TGraph = record
    Nodes: TDictionary<TNodeId, TNode>;
    Edges: TDictionary<TEdgeId, TEdge>;
  end;

implementation

end.
