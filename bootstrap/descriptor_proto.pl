% -*- mode: Prolog -*-

% Inputs a .proto.wire file and outputs a Prolog term that represents
% the same data. The .proto.wire file can be created by:
%     protoc --descriptor_set_out=___.proto.wire

% The protobuf metadata is in descriptor_proto/1, which is derived
% from descriptor.proto (libprotoc 3.6.1). Eventually, this will be bootstrapped
% to use the .proto.wire data; but for now, the process is:
%     protoc --include_imports --descriptor_set_out=descriptor.proto.wire \
%       -I$HOME/src/protobuf/src/google/protobuf \
%       descriptor.proto
%     protoc -I. -I$HOME/src/protobuf/src/google/protobuf \
%       --decode=google.protobuf.FileDescriptorSet \
%       descriptor.proto \
%       < descriptor.proto.wire
%       > descriptor.proto.wiredump
%   And then run use parse_descriptor_proto_dump.pl:
%     ?- parse_descriptor('descriptor.proto.wiredump').

:- module(descriptor_proto,
    [ % Term expansion of descriptor_proto/1 creates the following facts
      % see descriptor_proto_expand.pl
     protobufs:package/3,
     protobufs:message_type/3,
     protobufs:field_name/4,
     protobufs:field_json_name/2,
     protobufs:field_label/2,
     protobufs:field_type/2,
     protobufs:field_type_name/2,
     protobufs:field_default_value/2,
     protobufs:field_option_packed/1,
     protobufs:enum_type/3,
     protobufs:enum_value/3,
     main/0
    ]).

:- use_module(descriptor_proto_expand, [descriptor_proto_expand_FileDescriptorSet/2]).
:- use_module(library(readutil), [read_stream_to_codes/3]).
:- use_module(library(protobufs)).
:- use_module(library(debug)).

:- initialization(main, main).

main :-
    sanity_check,
    set_stream(user_input, encoding(octet)),
    set_stream(user_input, type(binary)),
    read_stream_to_codes(user_input, WireFormat),
    protobuf_segment_message(Segments, WireFormat),
    % protobuf_segment_message/2 can leave choicepoints, and we don't
    % want to backtrack through all the possibilities because that
    % leads to combinatoric explosion; instead use
    % protobuf_segment_convert/2 to change segments that were guessed
    % incorrectly.
    !, % don't use any other possible Segments - let protobuf_segment_convert/2 do the job
    maplist(segment_to_term('.google.protobuf.FileDescriptorSet'), Segments, Msg),
    maplist(write_metadata, Msg).

write_metadata(field_and_value(file,repeat,FileDescriptor)) =>
    FileDescriptor >:< '.google.protobuf.FileDescriptorProto'{name:FileName},
    print_term_cleaned(protobuf_metadata(FileName, FileDescriptor), [indent_arguments(4)], MsgStr),
    write(user_output, MsgStr),
    writeln(user_output, '.').

:- det(sanity_check/0).
sanity_check :-
    forall(protobufs:field_name(Fqn, Num, FN, FqnN), protobufs:field_label(FqnN, _LabelRepeatOptional)),
    forall(protobufs:field_name(Fqn, Num, FN, FqnN), protobufs:field_type_name(FqnN, _Type)).

:- det(segment_to_term/3).
%! segment_to_term(+ContextType:atom, +Segment, -FieldAndValue) is det.
% ContextType is the type (name) of the containing message
% Segment is a segment from protobuf_segment_message/2
% TODO: if performance is an issue, this code can be combined with
%       protobuf_segment_message/2 (and thereby avoid the use of protobuf_segment_convert/2)
segment_to_term(ContextType0, Segment0, FieldAndValue) =>
    segment_type_tag(Segment0, _, Tag),
    field_and_type(ContextType0, Tag, FieldName, _FqnName, ContextType, RepeatOptional, Type),
    convert_segment(Type, ContextType, Segment0, Segment),
    FieldAndValue = field_and_value(FieldName,RepeatOptional,Segment).

% TODO: protobufs:segment_type_tag/3
segment_type_tag(varint(Tag,_Codes),           varint,           Tag).
segment_type_tag(fixed64(Tag,_Codes),          fixed64,          Tag).
segment_type_tag(start_group(Tag),             start_group,      Tag).
segment_type_tag(end_group(Tag),               end_group,        Tag).
segment_type_tag(fixed32(Tag,_Codes),          fixed32,          Tag).
segment_type_tag(length_delimited(Tag,_Codes), length_delimited, Tag).
segment_type_tag(message(Tag,_Segments),       length_delimited, Tag).
segment_type_tag(packed(Tag,_Compound),        length_delimited, Tag).
segment_type_tag(string(Tag,_String),          length_delimited, Tag).

:- det(convert_segment/4).
%! convert_segment(+Type:atom, +Segment, -Value) is det.
% Compute an appropriate =Value= from the combination of descriptor
% "type" (in =Type=) and a =Segment=.
convert_segment('TYPE_DOUBLE', _ContextType, Segment0, Value) =>
    Segment = fixed64(_Tag,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    float64_codes(Value, Codes).
convert_segment('TYPE_FLOAT', _ContextType, Segment0, Value) =>
    Segment = fixed32(_Tag,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    float32_codes(Value, Codes).
convert_segment('TYPE_INT64', _ContextType, Segment0, Value) =>
    Segment = varint(_Tag,Value),
    protobuf_segment_convert(Segment0, Segment), !.
convert_segment('TYPE_UINT64', _ContextType, Segment0, Value) =>
    Segment = varint(_Tag,Value),
    protobuf_segment_convert(Segment0, Segment), !.
convert_segment('TYPE_INT32', _ContextType, Segment0, Value) =>
    Segment = varint(_Tag,Value),
    protobuf_segment_convert(Segment0, Segment), !.
convert_segment('TYPE_FIXED64', _ContextType, Segment0, Value) =>
    Segment = fixed64(_Tag,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    int64_codes(Value, Codes).
convert_segment('TYPE_FIXED32', _ContextType, Segment0, Value) =>
    Segment = fixed32(_Tag,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    int32_codes(Value, Codes).
convert_segment('TYPE_BOOL', _ContextType, Segment0, Value) =>
    Segment = varint(_Tag,Value0),
    protobuf_segment_convert(Segment0, Segment), !,
    int_bool(Value0, Value).
convert_segment('TYPE_STRING', _ContextType, Segment0, Value) =>
    Segment = string(_,ValueStr),
    protobuf_segment_convert(Segment0, Segment), !,
    (   true     % TODO: control whether atom or string with an option
    ->  atom_string(Value, ValueStr)
    ;   Value = ValueStr
    ).
convert_segment('TYPE_GROUP', _ContextType, _Segment0, _Value) =>
    fail. % TODO - for now, this will throw an exception because of :- det(convert_segment/4).
convert_segment('TYPE_MESSAGE', ContextType, Segment0, Value) =>
    Segment = message(_,MsgSegments),
    protobuf_segment_convert(Segment0, Segment), !,
    maplist(segment_to_term(ContextType), MsgSegments, MsgFields),
    combine_fields(MsgFields, ContextType{}, Value).
convert_segment('TYPE_BYTES', _ContextType, Segment0, Value) =>
    Segment = length_delimited(_,Value),
    protobuf_segment_convert(Segment0, Segment), !.
convert_segment('TYPE_UINT32', _ContextType, Segment0, Value) =>
    Segment = varint(_Tag,Value),
    protobuf_segment_convert(Segment0, Segment), !.
convert_segment('TYPE_ENUM', ContextType, Segment0, Value) =>
    Segment = varint(_,Value0),
    protobuf_segment_convert(Segment0, Segment), !,
    proto_enum_value(ContextType, Value, Value0).
convert_segment('TYPE_SFIXED32', _ContextType, Segment0, Value) =>
    Segment = fixed32(_,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    int32_codes(Value, Codes).
convert_segment('TYPE_SFIXED64', _ContextType, Segment0, Value) =>
    Segment = fixed64(_,Codes),
    protobuf_segment_convert(Segment0, Segment), !,
    int64_codes(Value, Codes).
convert_segment('TYPE_SINT32', _ContextType, Segment0, Value) =>
    Segment = varint(_,Value0),
    protobuf_segment_convert(Segment0, Segment), !,
    integer_zigzag(Value, Value0).
convert_segment('TYPE_SINT64', _ContextType, Segment0, Value) =>
    Segment = varint(_,Value0),
    protobuf_segment_convert(Segment0, Segment), !,
    integer_zigzag(Value, Value0).

int_bool(0, false).
int_bool(1, true).

:- det(combine_fields/3).
%! combine_fields(+Fields:list, +MsgDict0, -MsgDict) is det.
% Combines the fields into a dict.
% If the field is marked as 'norepeat' (optional/required), then the last
%    occurrence is kept (as per the protobuf wire spec)
% If the field is marked as 'repeat', then all the occurrences
%    are put into a list, in order.
% Assume that fields normally occur all together, but can handle
% (less efficiently) fields not occurring togeter, as is allowed
% by the protobuf spec.
combine_fields([], MsgDict0, MsgDict) => MsgDict = MsgDict0.
combine_fields([field_and_value(Field,norepeat,Value)|Fields], MsgDict0, MsgDict) =>
    put_dict(Field, MsgDict0, Value, MsgDict1),
    combine_fields(Fields, MsgDict1, MsgDict).
combine_fields([field_and_value(Field,repeat,Value)|Fields], MsgDict0, MsgDict) =>
    combine_fields_repeat(Fields, Field, NewValues, RestFields),
    (   get_dict(Field, MsgDict0, ExistingValues)
    ->  append(ExistingValues, [Value|NewValues], Values)
    ;   Values = [Value|NewValues]
    ),
    put_dict(Field, MsgDict0, Values, MsgDict1),
    combine_fields(RestFields, MsgDict1, MsgDict).

:- det(combine_fields_repeat/4).
%! combine_fields_repeat(+Fields:list, Field:atom, -Values:list, RestFields:list) is det.
% Helper for combine_fields/3
% Stops at the first item that doesn't match =Field= - the assumption
% is that all the items for a field will be together and if they're
% not, they would be combined outside this predicate.
%
% @param Fields a list of fields (Field-Repeat-Value)
% @param Field the name of the field that is being combined
% @param Values gets the Value items that match Field
% @param RestFields gets any left-over fields
combine_fields_repeat([], _Field, Values, RestFields) => Values = [], RestFields = [].
combine_fields_repeat([Field-repeat-Value|Fields], Field, Values, RestFields) =>
    Values = [Value|Values2],
    combine_fields_repeat(Fields, Field, Values2, RestFields).
combine_fields_repeat(Fields, _Field, Values, RestFields) => Values = [], RestFields = Fields.

:- det(field_and_type/7).
%! field_and_type(+ContextType:atom, +Tag:int, -FieldName:atom, -FqnName:atom, -ContextType2:atom, -RepeatOptional:atom, -Type:atom) is det.
% Lookup a =ContextType= and =Tag= to get the field name, type, etc.
field_and_type(ContextType, Tag, FieldName, FqnName, ContextType2, RepeatOptional, Type) =>
    protobufs:field_name(ContextType, Tag, FieldName, FqnName),
    protobufs:field_type_name(FqnName, ContextType2),
    fqn_repeat_optional(FqnName, RepeatOptional),
    protobufs:field_type(FqnName, Type).

%! fqn_repeat_optional(+FqnName:atom, -RepeatOptional:atom) is det.
% Lookup up protobufs:field_label(FqnName, _), protobufs:field_option_packed(FqnName)
% and set RepeatOptional to one of
% =norepeat=, =repeat=, =repeat_packed=.
fqn_repeat_optional(FqnName, RepeatOptional) =>
    protobufs:field_label(FqnName, LabelRepeatOptional),
    (   LabelRepeatOptional = 'LABEL_REPEATED',
        protobufs:field_option_packed(FqnName)
    ->  RepeatOptional = repeat_packed
    ;   \+ protobufs:field_option_packed(FqnName), % validity check
        fqn_repeat_optional_2(LabelRepeatOptional, RepeatOptional)
    ).

:- det(fqn_repeat_optional_2/2).
%! fqn_repeat_optional_2(+DescriptorLabelEnum:atom, -RepeatOrEmpty:atom) is det.
% Map the descriptor "label" to 'repeat' or 'norepeat'.
fqn_repeat_optional_2('LABEL_OPTIONAL', norepeat).
fqn_repeat_optional_2('LABEL_REQUIRED', norepeat).
fqn_repeat_optional_2('LABEL_REPEATED', repeat).

%! field_descriptor_label_repeated(+Label:atom) is semidet.
% From message FieldDescriptorProto enum Label
field_descriptor_label_repeated('LABEL_REPEATED').

%! field_descriptor_label_single(+Label:atom) is semidet.
% From message FieldDescriptorProto enum Label
field_descriptor_label_single('LABEL_OPTIONAL').
field_descriptor_label_single('LABEL_REQUIRED').

:- det(print_term_cleaned/3).
%! print_term_cleaned(+Term, +Options, -TermStr) is det.
% print_term, cleaned up
print_term_cleaned(Term, Options, TermStr) =>
    % print_term leaves trailing whitespace, so remove it
    with_output_to(
            string(TermStr0),
            (current_output(TermStream),
             print_term(Term, [output(TermStream)|Options]))),
    re_replace(" +\n"/g, "\n", TermStr0, TermStr1),
    re_replace("\t"/g, "        ", TermStr1, TermStr).

%! term_expansion(+Term, -Expansion) is semidet.
% Term expansion for =|descriptor_set(Set)|=.
term_expansion(descriptor_set(Set), Expansion) :-
    descriptor_proto_expand_FileDescriptorSet(Set, Expansion).

%! descriptor_set(-Set) is det.
% descriptor_set/1 is expanded using
% descriptor_set_expand:descriptor_proto_expand_FileDescriptorSet//1.
%
% It was generated by running parse_descriptor_proto_dump.pl
% (parse_descriptor/0) over the output of protoc --decode=FileDescriptorSet
% (see Makefile rule plugin.proto.parse).
descriptor_set(
'FileDescriptorSet'{
    file:[ 'FileDescriptorProto'{
               dependency:'',
               message_type:[ 'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:file,
                                              label:'LABEL_REPEATED',
                                              name:file,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FileDescriptorProto'
                                            }
                                        ],
                                  name:'FileDescriptorSet',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:package,
                                              label:'LABEL_OPTIONAL',
                                              name:package,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:dependency,
                                              label:'LABEL_REPEATED',
                                              name:dependency,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:publicDependency,
                                              label:'LABEL_REPEATED',
                                              name:public_dependency,
                                              number:10,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:weakDependency,
                                              label:'LABEL_REPEATED',
                                              name:weak_dependency,
                                              number:11,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:messageType,
                                              label:'LABEL_REPEATED',
                                              name:message_type,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.DescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:enumType,
                                              label:'LABEL_REPEATED',
                                              name:enum_type,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:service,
                                              label:'LABEL_REPEATED',
                                              name:service,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.ServiceDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:extension,
                                              label:'LABEL_REPEATED',
                                              name:extension,
                                              number:7,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FieldDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:8,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FileOptions'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:sourceCodeInfo,
                                              label:'LABEL_OPTIONAL',
                                              name:source_code_info,
                                              number:9,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.SourceCodeInfo'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:syntax,
                                              label:'LABEL_OPTIONAL',
                                              name:syntax,
                                              number:12,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            }
                                        ],
                                  name:'FileDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:field,
                                              label:'LABEL_REPEATED',
                                              name:field,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FieldDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:extension,
                                              label:'LABEL_REPEATED',
                                              name:extension,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FieldDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:nestedType,
                                              label:'LABEL_REPEATED',
                                              name:nested_type,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.DescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:enumType,
                                              label:'LABEL_REPEATED',
                                              name:enum_type,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:extensionRange,
                                              label:'LABEL_REPEATED',
                                              name:extension_range,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.DescriptorProto.ExtensionRange'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:oneofDecl,
                                              label:'LABEL_REPEATED',
                                              name:oneof_decl,
                                              number:8,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.OneofDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:7,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.MessageOptions'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:reservedRange,
                                              label:'LABEL_REPEATED',
                                              name:reserved_range,
                                              number:9,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.DescriptorProto.ReservedRange'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:reservedName,
                                              label:'LABEL_REPEATED',
                                              name:reserved_name,
                                              number:10,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            }
                                        ],
                                  name:'DescriptorProto',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:start,
                                                                label:'LABEL_OPTIONAL',
                                                                name:start,
                                                                number:1,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:end,
                                                                label:'LABEL_OPTIONAL',
                                                                name:end,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:options,
                                                                label:'LABEL_OPTIONAL',
                                                                name:options,
                                                                number:3,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_MESSAGE',
                                                                type_name:'.google.protobuf.ExtensionRangeOptions'
                                                              }
                                                          ],
                                                    name:'ExtensionRange',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  },
                                                'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:start,
                                                                label:'LABEL_OPTIONAL',
                                                                name:start,
                                                                number:1,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:end,
                                                                label:'LABEL_OPTIONAL',
                                                                name:end,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              }
                                                          ],
                                                    name:'ReservedRange',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'ExtensionRangeOptions',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[ 'EnumDescriptorProto'{
                                                  name:'Type',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'TYPE_DOUBLE',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_FLOAT',
                                                              number:2
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_INT64',
                                                              number:3
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_UINT64',
                                                              number:4
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_INT32',
                                                              number:5
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_FIXED64',
                                                              number:6
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_FIXED32',
                                                              number:7
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_BOOL',
                                                              number:8
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_STRING',
                                                              number:9
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_GROUP',
                                                              number:10
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_MESSAGE',
                                                              number:11
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_BYTES',
                                                              number:12
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_UINT32',
                                                              number:13
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_ENUM',
                                                              number:14
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_SFIXED32',
                                                              number:15
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_SFIXED64',
                                                              number:16
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_SINT32',
                                                              number:17
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'TYPE_SINT64',
                                                              number:18
                                                            }
                                                        ]
                                                },
                                              'EnumDescriptorProto'{
                                                  name:'Label',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'LABEL_OPTIONAL',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'LABEL_REQUIRED',
                                                              number:2
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'LABEL_REPEATED',
                                                              number:3
                                                            }
                                                        ]
                                                }
                                            ],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:number,
                                              label:'LABEL_OPTIONAL',
                                              name:number,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:label,
                                              label:'LABEL_OPTIONAL',
                                              name:label,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.FieldDescriptorProto.Label'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:type,
                                              label:'LABEL_OPTIONAL',
                                              name:type,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.FieldDescriptorProto.Type'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:typeName,
                                              label:'LABEL_OPTIONAL',
                                              name:type_name,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:extendee,
                                              label:'LABEL_OPTIONAL',
                                              name:extendee,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:defaultValue,
                                              label:'LABEL_OPTIONAL',
                                              name:default_value,
                                              number:7,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:oneofIndex,
                                              label:'LABEL_OPTIONAL',
                                              name:oneof_index,
                                              number:9,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:jsonName,
                                              label:'LABEL_OPTIONAL',
                                              name:json_name,
                                              number:10,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:8,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FieldOptions'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:proto3Optional,
                                              label:'LABEL_OPTIONAL',
                                              name:proto3_optional,
                                              number:17,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            }
                                        ],
                                  name:'FieldDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.OneofOptions'
                                            }
                                        ],
                                  name:'OneofDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:value,
                                              label:'LABEL_REPEATED',
                                              name:value,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumValueDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumOptions'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:reservedRange,
                                              label:'LABEL_REPEATED',
                                              name:reserved_range,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumDescriptorProto.EnumReservedRange'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:reservedName,
                                              label:'LABEL_REPEATED',
                                              name:reserved_name,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            }
                                        ],
                                  name:'EnumDescriptorProto',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:start,
                                                                label:'LABEL_OPTIONAL',
                                                                name:start,
                                                                number:1,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:end,
                                                                label:'LABEL_OPTIONAL',
                                                                name:end,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              }
                                                          ],
                                                    name:'EnumReservedRange',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:number,
                                              label:'LABEL_OPTIONAL',
                                              name:number,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.EnumValueOptions'
                                            }
                                        ],
                                  name:'EnumValueDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:method,
                                              label:'LABEL_REPEATED',
                                              name:method,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.MethodDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.ServiceOptions'
                                            }
                                        ],
                                  name:'ServiceDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_OPTIONAL',
                                              name:name,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:inputType,
                                              label:'LABEL_OPTIONAL',
                                              name:input_type,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:outputType,
                                              label:'LABEL_OPTIONAL',
                                              name:output_type,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:options,
                                              label:'LABEL_OPTIONAL',
                                              name:options,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.MethodOptions'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:clientStreaming,
                                              label:'LABEL_OPTIONAL',
                                              name:client_streaming,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:serverStreaming,
                                              label:'LABEL_OPTIONAL',
                                              name:server_streaming,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            }
                                        ],
                                  name:'MethodDescriptorProto',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[ 'EnumDescriptorProto'{
                                                  name:'OptimizeMode',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'SPEED',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'CODE_SIZE',
                                                              number:2
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'LITE_RUNTIME',
                                                              number:3
                                                            }
                                                        ]
                                                }
                                            ],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:javaPackage,
                                              label:'LABEL_OPTIONAL',
                                              name:java_package,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:javaOuterClassname,
                                              label:'LABEL_OPTIONAL',
                                              name:java_outer_classname,
                                              number:8,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:javaMultipleFiles,
                                              label:'LABEL_OPTIONAL',
                                              name:java_multiple_files,
                                              number:10,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:javaGenerateEqualsAndHash,
                                              label:'LABEL_OPTIONAL',
                                              name:java_generate_equals_and_hash,
                                              number:20,
                                              options:'FieldOptions'{
                                                          deprecated:true,
                                                          packed:''
                                                        },
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:javaStringCheckUtf8,
                                              label:'LABEL_OPTIONAL',
                                              name:java_string_check_utf8,
                                              number:27,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'SPEED',
                                              json_name:optimizeFor,
                                              label:'LABEL_OPTIONAL',
                                              name:optimize_for,
                                              number:9,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.FileOptions.OptimizeMode'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:goPackage,
                                              label:'LABEL_OPTIONAL',
                                              name:go_package,
                                              number:11,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:ccGenericServices,
                                              label:'LABEL_OPTIONAL',
                                              name:cc_generic_services,
                                              number:16,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:javaGenericServices,
                                              label:'LABEL_OPTIONAL',
                                              name:java_generic_services,
                                              number:17,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:pyGenericServices,
                                              label:'LABEL_OPTIONAL',
                                              name:py_generic_services,
                                              number:18,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:phpGenericServices,
                                              label:'LABEL_OPTIONAL',
                                              name:php_generic_services,
                                              number:42,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:23,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:true,
                                              json_name:ccEnableArenas,
                                              label:'LABEL_OPTIONAL',
                                              name:cc_enable_arenas,
                                              number:31,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:objcClassPrefix,
                                              label:'LABEL_OPTIONAL',
                                              name:objc_class_prefix,
                                              number:36,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:csharpNamespace,
                                              label:'LABEL_OPTIONAL',
                                              name:csharp_namespace,
                                              number:37,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:swiftPrefix,
                                              label:'LABEL_OPTIONAL',
                                              name:swift_prefix,
                                              number:39,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:phpClassPrefix,
                                              label:'LABEL_OPTIONAL',
                                              name:php_class_prefix,
                                              number:40,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:phpNamespace,
                                              label:'LABEL_OPTIONAL',
                                              name:php_namespace,
                                              number:41,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:phpMetadataNamespace,
                                              label:'LABEL_OPTIONAL',
                                              name:php_metadata_namespace,
                                              number:44,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:rubyPackage,
                                              label:'LABEL_OPTIONAL',
                                              name:ruby_package,
                                              number:45,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'FileOptions',
                                  nested_type:[],
                                  reserved_range:[ 'EnumReservedRange'{
                                                       end:39,
                                                       start:38
                                                     }
                                                 ]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:messageSetWireFormat,
                                              label:'LABEL_OPTIONAL',
                                              name:message_set_wire_format,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:noStandardDescriptorAccessor,
                                              label:'LABEL_OPTIONAL',
                                              name:no_standard_descriptor_accessor,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:mapEntry,
                                              label:'LABEL_OPTIONAL',
                                              name:map_entry,
                                              number:7,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'MessageOptions',
                                  nested_type:[],
                                  reserved_range:[ 'EnumReservedRange'{
                                                       end:5,
                                                       start:4
                                                     },
                                                   'EnumReservedRange'{
                                                       end:6,
                                                       start:5
                                                     },
                                                   'EnumReservedRange'{
                                                       end:7,
                                                       start:6
                                                     },
                                                   'EnumReservedRange'{
                                                       end:9,
                                                       start:8
                                                     },
                                                   'EnumReservedRange'{
                                                       end:10,
                                                       start:9
                                                     }
                                                 ]
                                },
                              'DescriptorProto'{
                                  enum_type:[ 'EnumDescriptorProto'{
                                                  name:'CType',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'STRING',
                                                              number:0
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'CORD',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'STRING_PIECE',
                                                              number:2
                                                            }
                                                        ]
                                                },
                                              'EnumDescriptorProto'{
                                                  name:'JSType',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'JS_NORMAL',
                                                              number:0
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'JS_STRING',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'JS_NUMBER',
                                                              number:2
                                                            }
                                                        ]
                                                }
                                            ],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'STRING',
                                              json_name:ctype,
                                              label:'LABEL_OPTIONAL',
                                              name:ctype,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.FieldOptions.CType'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:packed,
                                              label:'LABEL_OPTIONAL',
                                              name:packed,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'JS_NORMAL',
                                              json_name:jstype,
                                              label:'LABEL_OPTIONAL',
                                              name:jstype,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.FieldOptions.JSType'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:lazy,
                                              label:'LABEL_OPTIONAL',
                                              name:lazy,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:weak,
                                              label:'LABEL_OPTIONAL',
                                              name:weak,
                                              number:10,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'FieldOptions',
                                  nested_type:[],
                                  reserved_range:[ 'EnumReservedRange'{
                                                       end:5,
                                                       start:4
                                                     }
                                                 ]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'OneofOptions',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:allowAlias,
                                              label:'LABEL_OPTIONAL',
                                              name:allow_alias,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'EnumOptions',
                                  nested_type:[],
                                  reserved_range:[ 'EnumReservedRange'{
                                                       end:6,
                                                       start:5
                                                     }
                                                 ]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'EnumValueOptions',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:33,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'ServiceOptions',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[ 'EnumDescriptorProto'{
                                                  name:'IdempotencyLevel',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'IDEMPOTENCY_UNKNOWN',
                                                              number:0
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'NO_SIDE_EFFECTS',
                                                              number:1
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'IDEMPOTENT',
                                                              number:2
                                                            }
                                                        ]
                                                }
                                            ],
                                  extension_range:[ 'ExtensionRange'{
                                                        end:536870912,
                                                        start:1000
                                                      }
                                                  ],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:false,
                                              json_name:deprecated,
                                              label:'LABEL_OPTIONAL',
                                              name:deprecated,
                                              number:33,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BOOL',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'IDEMPOTENCY_UNKNOWN',
                                              json_name:idempotencyLevel,
                                              label:'LABEL_OPTIONAL',
                                              name:idempotency_level,
                                              number:34,
                                              options:'FieldOptions'{},
                                              type:'TYPE_ENUM',
                                              type_name:'.google.protobuf.MethodOptions.IdempotencyLevel'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:uninterpretedOption,
                                              label:'LABEL_REPEATED',
                                              name:uninterpreted_option,
                                              number:999,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption'
                                            }
                                        ],
                                  name:'MethodOptions',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:name,
                                              label:'LABEL_REPEATED',
                                              name:name,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.UninterpretedOption.NamePart'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:identifierValue,
                                              label:'LABEL_OPTIONAL',
                                              name:identifier_value,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:positiveIntValue,
                                              label:'LABEL_OPTIONAL',
                                              name:positive_int_value,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_UINT64',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:negativeIntValue,
                                              label:'LABEL_OPTIONAL',
                                              name:negative_int_value,
                                              number:5,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT64',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:doubleValue,
                                              label:'LABEL_OPTIONAL',
                                              name:double_value,
                                              number:6,
                                              options:'FieldOptions'{},
                                              type:'TYPE_DOUBLE',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:stringValue,
                                              label:'LABEL_OPTIONAL',
                                              name:string_value,
                                              number:7,
                                              options:'FieldOptions'{},
                                              type:'TYPE_BYTES',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:aggregateValue,
                                              label:'LABEL_OPTIONAL',
                                              name:aggregate_value,
                                              number:8,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            }
                                        ],
                                  name:'UninterpretedOption',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:namePart,
                                                                label:'LABEL_REQUIRED',
                                                                name:name_part,
                                                                number:1,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:isExtension,
                                                                label:'LABEL_REQUIRED',
                                                                name:is_extension,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_BOOL',
                                                                type_name:''
                                                              }
                                                          ],
                                                    name:'NamePart',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:location,
                                              label:'LABEL_REPEATED',
                                              name:location,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.SourceCodeInfo.Location'
                                            }
                                        ],
                                  name:'SourceCodeInfo',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:path,
                                                                label:'LABEL_REPEATED',
                                                                name:path,
                                                                number:1,
                                                                options:'FieldOptions'{
                                                                            deprecated:'',
                                                                            packed:true
                                                                          },
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:span,
                                                                label:'LABEL_REPEATED',
                                                                name:span,
                                                                number:2,
                                                                options:'FieldOptions'{
                                                                            deprecated:'',
                                                                            packed:true
                                                                          },
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:leadingComments,
                                                                label:'LABEL_OPTIONAL',
                                                                name:leading_comments,
                                                                number:3,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:trailingComments,
                                                                label:'LABEL_OPTIONAL',
                                                                name:trailing_comments,
                                                                number:4,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:leadingDetachedComments,
                                                                label:'LABEL_REPEATED',
                                                                name:leading_detached_comments,
                                                                number:6,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              }
                                                          ],
                                                    name:'Location',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:annotation,
                                              label:'LABEL_REPEATED',
                                              name:annotation,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.GeneratedCodeInfo.Annotation'
                                            }
                                        ],
                                  name:'GeneratedCodeInfo',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:path,
                                                                label:'LABEL_REPEATED',
                                                                name:path,
                                                                number:1,
                                                                options:'FieldOptions'{
                                                                            deprecated:'',
                                                                            packed:true
                                                                          },
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:sourceFile,
                                                                label:'LABEL_OPTIONAL',
                                                                name:source_file,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:begin,
                                                                label:'LABEL_OPTIONAL',
                                                                name:begin,
                                                                number:3,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:end,
                                                                label:'LABEL_OPTIONAL',
                                                                name:end,
                                                                number:4,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_INT32',
                                                                type_name:''
                                                              }
                                                          ],
                                                    name:'Annotation',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                }
                            ],
               name:'descriptor.proto',
               options:'FileOptions'{
                           cc_enable_arenas:true,
                           csharp_namespace:'Google.Protobuf.Reflection',
                           go_package:'google.golang.org/protobuf/types/descriptorpb',
                           java_outer_classname:'DescriptorProtos',
                           java_package:'com.google.protobuf',
                           objc_class_prefix:'GPB',
                           optimize_for:'SPEED'
                         },
               package:'google.protobuf'
             },
           'FileDescriptorProto'{
               dependency:'google/protobuf/descriptor.proto',
               message_type:[ 'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:major,
                                              label:'LABEL_OPTIONAL',
                                              name:major,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:minor,
                                              label:'LABEL_OPTIONAL',
                                              name:minor,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:patch,
                                              label:'LABEL_OPTIONAL',
                                              name:patch,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_INT32',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:suffix,
                                              label:'LABEL_OPTIONAL',
                                              name:suffix,
                                              number:4,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            }
                                        ],
                                  name:'Version',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:fileToGenerate,
                                              label:'LABEL_REPEATED',
                                              name:file_to_generate,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:parameter,
                                              label:'LABEL_OPTIONAL',
                                              name:parameter,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:protoFile,
                                              label:'LABEL_REPEATED',
                                              name:proto_file,
                                              number:15,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.FileDescriptorProto'
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:compilerVersion,
                                              label:'LABEL_OPTIONAL',
                                              name:compiler_version,
                                              number:3,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.compiler.Version'
                                            }
                                        ],
                                  name:'CodeGeneratorRequest',
                                  nested_type:[],
                                  reserved_range:[]
                                },
                              'DescriptorProto'{
                                  enum_type:[ 'EnumDescriptorProto'{
                                                  name:'Feature',
                                                  value:[ 'EnumValueDescriptorProto'{
                                                              name:'FEATURE_NONE',
                                                              number:0
                                                            },
                                                          'EnumValueDescriptorProto'{
                                                              name:'FEATURE_PROTO3_OPTIONAL',
                                                              number:1
                                                            }
                                                        ]
                                                }
                                            ],
                                  extension_range:[],
                                  field:[ 'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:error,
                                              label:'LABEL_OPTIONAL',
                                              name:error,
                                              number:1,
                                              options:'FieldOptions'{},
                                              type:'TYPE_STRING',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:supportedFeatures,
                                              label:'LABEL_OPTIONAL',
                                              name:supported_features,
                                              number:2,
                                              options:'FieldOptions'{},
                                              type:'TYPE_UINT64',
                                              type_name:''
                                            },
                                          'FieldDescriptorProto'{
                                              default_value:'',
                                              json_name:file,
                                              label:'LABEL_REPEATED',
                                              name:file,
                                              number:15,
                                              options:'FieldOptions'{},
                                              type:'TYPE_MESSAGE',
                                              type_name:'.google.protobuf.compiler.CodeGeneratorResponse.File'
                                            }
                                        ],
                                  name:'CodeGeneratorResponse',
                                  nested_type:[ 'DescriptorProto'{
                                                    enum_type:[],
                                                    extension_range:[],
                                                    field:[ 'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:name,
                                                                label:'LABEL_OPTIONAL',
                                                                name:name,
                                                                number:1,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:insertionPoint,
                                                                label:'LABEL_OPTIONAL',
                                                                name:insertion_point,
                                                                number:2,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:content,
                                                                label:'LABEL_OPTIONAL',
                                                                name:content,
                                                                number:15,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_STRING',
                                                                type_name:''
                                                              },
                                                            'FieldDescriptorProto'{
                                                                default_value:'',
                                                                json_name:generatedCodeInfo,
                                                                label:'LABEL_OPTIONAL',
                                                                name:generated_code_info,
                                                                number:16,
                                                                options:'FieldOptions'{},
                                                                type:'TYPE_MESSAGE',
                                                                type_name:'.google.protobuf.GeneratedCodeInfo'
                                                              }
                                                          ],
                                                    name:'File',
                                                    nested_type:[],
                                                    reserved_range:[]
                                                  }
                                              ],
                                  reserved_range:[]
                                }
                            ],
               name:'plugin.proto',
               options:'FileOptions'{
                           cc_enable_arenas:'',
                           csharp_namespace:'',
                           go_package:'google.golang.org/protobuf/types/pluginpb',
                           java_outer_classname:'PluginProtos',
                           java_package:'com.google.protobuf.compiler',
                           objc_class_prefix:'',
                           optimize_for:''
                         },
               package:'google.protobuf.compiler'
             }
         ]
  }).

end_of_file.
