;{- Code Header
; ==- Basic Info -================================
;         Name: BasicDomainNameServer.pb
;      Version: N/A
;      Authors: Herwin Bozet
;  Create date: 9 June ‎2019, 21:04:51
; 
;  Description: A very primitive DNS server.
;               This is more of a 'POC' to learn about networking in PB and the DNS protocol.
; 
; ==- Requirements -=============================
;  Endianness.pbi:
;    Version: 1.0.2
;       Link: https://github.com/aziascreations/PB-Utils
;    License: WTFPL
; 
; ==- Compatibility -=============================
;  Compiler version: PureBasic 5.70 (x64) (Other versions untested)
;  Operating system: Windows 10 (Other platforms untested)
; 
; ==- Links & License -===========================
;   Github: N/A
;  License: Unlicense
; 
; ==- Documentation -=============================
;  DNS RFCs:
;    https://tools.ietf.org/html/rfc1035
;    https://tools.ietf.org/html/rfc3425
;      Obseletes IQUERY opcode in preferences of pointer (PTR) records in the in-addr.arpa tree.
;  
;  Other RFCs:
;    https://tools.ietf.org/html/rfc8375
;  
;  ???: (IQUERY)
;    http://www-inf.int-evry.fr/~hennequi/CoursDNS/NOTES-COURS_eng/msg.html
;}

; This server follows the following RFCs:
;   * 1035 (partially)
;   * ???
;   * 3425 (completely) - "Obsoleting IQUERY" - (Will be parsed, but responded to by a unimplemented error code.)
;       It has been implemented since Windows throws them willy nilly.
;   * 8375 (partially) - *.home.arpa domains - (Just mentions of it are implmemented for testing purposes)
;       https://tools.ietf.org/html/rfc8375


; https://www.rfc-editor.org/rfc/rfc3596.txt
;   For the AAAA type (ipv6)

;
;- Compiler directives & imports
;{

EnableExplicit

XIncludeFile "./PB-Utils/Includes/Endianness.pbi"

;}

;
;- DNS standard stuff
;

; FIXME:
;   See p32 about the size over UDP and a related flag.

; FIXME:
;   If you want to create a packet yourself, be carefull for the endianness of the fields !

; FIXME:
;   NEVER use SizeOf() on DNSPacketHeaderFlags, DNSPacketHeader and DNSPacketEntry !
;   Use the provided constants and AllocateStructure() !


;-> Structures

; Decoded flags from a DNS packet header.
; This structure is used to avoid doing to much "binary operations".
Structure DNSPacketHeaderFlags
	QR.b     ; 0-query, 1-response (1 bit)
	Opcode.b ; See opcodes (4 bits)
	AA.b	 ; Authoritative Answer (1 bit) 0-? 1-?
	
	TC.b	 ; TrunCation - specifies that this message was truncated due To length greater than
			 ;  that permitted on the transmission channel. (1 bit)
	
	RD.b	 ; Recursion Desired - this bit may be set in a query and is copied into the response.
			 ; If RD is set, it directs the name server to pursue the query recursively.
			 ; Recursive query support is optional. (1 bit)
	
	RA.b     ; Recursion Available - this be is set or cleared in aresponse, and denotes whether
			 ;  recursive query support is available in the name server. (1 bit)
	
	Z.b      ; Reserved for future use.  Must be zero in all queries and responses. (3 bits)
			 ; Some of these bits are used by DNSSEC, they are not parsed as a separate value since 
			 ;  DNSSEC implementation is not the goal of this project.
	
	RCODE.b  ; Response code (4 bits)
EndStructure

; DNS packet header.
; RFC1035 p26-28
Structure DNSPacketHeader
	TransactionID.u
	
	FlagsWord.u
	Flags.DNSPacketHeaderFlags
	FlagsDecoded.b
	
	QuestionCount.u
	AnswerCount.u
	AuthorityCount.u ; NSCOUNT, Nameserver count
	AditionalRecordsCount.u
EndStructure


; ; DNS packet question section
; ; RFC1035 p28-29
; Structure DNSPacketQuestion
; 	;QNAME.s ; a domain name represented as a sequence of labels, where each label consists of
; 	;  a length octet followed by that number of octets.
; 	; The domain name terminates with the zero length octet for the null label of the root.
; 	; Note that this field may be an odd number of octets; no padding is used.
; 	
; 	List QNAMES.s() ; A list is used to allow easier manipulation of the data given in 'QNAME'.
; 					; The order goes as follow: 0 > n.
; 					;   eg: 0=Domain extension > 1=Domain name > 2->n=sub-domains...
; 					; There should be at least 2 entries, but it cannot be guaranteed. (At least 1 will be present - compression ???)
; 	
; 	; The full stuff if you don't want to play with the list, won't be read when composing a packet.
; 	; Use the list !
; 	;_QNAME$
; 	
; 	QTYPE.u ; Code which specifies the type of the query.
; 			; The values for this field include all codes valid for a TYPE field,
; 			;  together with some more general codes which can match more than one type of RR.
; 	
; 	QCLASS.u ; Specifies the class of the query.
; 			 ; For example, the QCLASS field is IN for the Internet.
; EndStructure

; I couldn't find a better name since the RFC insn't completely clear about the name.

Structure DNSPacketSection
	; GeneralOffset ; Might be used for compression.
	
	List NameParts.s()
	Name.s
	
	Type.u
	Class.u
EndStructure

Structure DNSPacketResourceRecord Extends DNSPacketSection
	TTL.l ; Should be unsigned !
	EffectiveTTL.q ; To deal with unsigned vars
	RDataLength.u
	RData.s
EndStructure

Structure DNSPacket
	Header.DNSPacketHeader
	
	List QuestionsRecords.DNSPacketSection()
	
	; RRs
	List AnswerRecords.DNSPacketResourceRecord()
	List AuthorityRecords.DNSPacketResourceRecord()
	List AditionalRecords.DNSPacketResourceRecord()
EndStructure


;-> Enumerations

Enumeration DNS_HEADER_OPCODES
	#DNS_OPCODE_QUERY   ; a standard query (QUERY)
	#DNS_OPCODE_IQUERY	; an inverse query (IQUERY)
	#DNS_OPCODE_STATUS	; a server status request (STATUS)
	
	; 3-15 - reserved for future use
	;#DNS_OPCODE_NOTIFY ; Database update notification (RFC1996) [?]
	;#DNS_OPCODE_UPDATE ; Dynamic database update (RFC2136) [?]
EndEnumeration

; The RCODES descriptions are copied from the RFCxxx document (See pN-M)
Enumeration DNS_HEADER_RCODES
	#DNS_RCODE_NO_ERROR = 0 ; No error condition
	#DNS_RCODE_FORMAT_ERROR = 1 ; The name server was unable To interpret the query.
	
	#DNS_RCODE_SERVER_FAILURE = 2 ;The name server was unable To process this query
								  ;  due to a problem with the name server.
	
	#DNS_RCODE_NAME_ERROR = 3 ; Meaningful only For responses from an authoritative name server,
							  ;  this code signifies that the domain name referenced in the query does not exist.
	
	#DNS_RCODE_NOT_IMPLEMENTED = 4 ; The name server does not support the requested kind of query.
	
	#DNS_RCODE_REFUSED = 5 ; The name server refuses to perform the specified operation for policy reasons.
						   ; For example, a name server may Not wish to provide the information To the particular requester,
						   ;  or a name server may not wish to perform a particular operation (e.g., zone transfer) for particular data.
	
	; 6-15 Reserved for future use
EndEnumeration

; Taken from RFC 1035 p12 & RFC 3596 p3
Enumeration DNS_RESOURCE_TYPE
	#DNS_RESOURCE_TYPE_A = 1      ; a host address
	#DNS_RESOURCE_TYPE_NS = 2	  ; an authoritative name server
	#DNS_RESOURCE_TYPE_MD = 3	  ; a mail destination (Obsolete - use MX)
	#DNS_RESOURCE_TYPE_MF = 4	  ; a mail forwarder (Obsolete - use MX)
	#DNS_RESOURCE_TYPE_CNAME = 5  ; the canonical name For an alias
	#DNS_RESOURCE_TYPE_SOA = 6	  ; marks the start of a zone of authority
	#DNS_RESOURCE_TYPE_MB = 7	  ; a mailbox domain name (EXPERIMENTAL)
	#DNS_RESOURCE_TYPE_MG = 8	  ; a mail group member (EXPERIMENTAL)
	#DNS_RESOURCE_TYPE_MR = 9	  ; a mail rename domain name (EXPERIMENTAL)
	#DNS_RESOURCE_TYPE_NULL = 10  ; a null RR (EXPERIMENTAL)
	#DNS_RESOURCE_TYPE_WKS = 11	  ; a well known service description
	#DNS_RESOURCE_TYPE_PTR = 12	  ; a domain name pointer
	#DNS_RESOURCE_TYPE_HINFO = 13 ; host information
	#DNS_RESOURCE_TYPE_MINFO = 14 ; mailbox Or mail List information
	#DNS_RESOURCE_TYPE_MX = 15	  ; mail exchange
	#DNS_RESOURCE_TYPE_TXT = 16	  ; text strings
	
	#DNS_RESOURCE_TYPE_AAAA = 28  ; a host address (ipv6) (RFC 3596 p3)
EndEnumeration

; QTYPE fields appear in the question part of a query.
; QTYPES are a superset of TYPEs, hence all TYPEs are valid QTYPEs.
; In addition, the following QTYPEs are defined:
Enumeration DNS_RESOURCE_QTYPE
	#DNS_RESOURCE_QTYPE_AXFR = 252  ; A request For a transfer of an entire zone
	#DNS_RESOURCE_QTYPE_MAILB = 253	; A request For mailbox-related records (MB, MG Or MR)
	#DNS_RESOURCE_QTYPE_MAILA = 254	; A request For mail agent RRs (Obsolete - see MX)
	#DNS_RESOURCE_QTYPE_ALL = 255	; A request For all records
EndEnumeration

Enumeration DNS_RESOURCE_CLASS
	#DNS_RESOURCE_CLASS_IN = 1 ; the Internet
	#DNS_RESOURCE_CLASS_CS = 2 ; the CSNET class (Obsolete - used only For examples in some obsolete RFCs)
	#DNS_RESOURCE_CLASS_CH = 3 ; the CHAOS class
	#DNS_RESOURCE_CLASS_HS = 4 ; Hesiod [Dyer 87]
EndEnumeration

; QCLASS fields appear in the question section of a query.
; QCLASS values are a superset of CLASS values; every CLASS is a valid QCLASS.
; In addition to CLASS values, the following QCLASSes are defined:
Enumeration DNS_RESOURCE_CLASS
	#DNS_RESOURCE_QCLASS_ANY = 255 ; any class
EndEnumeration


;
;-> Other constants
;{

; Protocol port.
#DNS_PORT = 53

; Used in place of "SizeOf(DNSPacketHeader)" since there are more fields in the structure.
; One of the RFCs (DNSSEC if I'm correct, it is an update to RFC1035) says it is 16 bytes long ???
#DNS_HEADER_SIZE = 12

; The maximum size for a DNS request over UDP allowed by the standard.
; TODO: Give where in the RFC
#DNS_PACKET_SIZE_MAX_UDP = 512

; DNS_ARPA_DOMAINS (https://en.wikipedia.org/wiki/DNS_zone#Internet_infrastructure_DNS_zones)
#DNS_DOMAIN_ARPA_ROOT$ = "arpa"
#DNS_DOMAIN_ARPA_IPV4$ = "in-addr"
#DNS_DOMAIN_ARPA_IPV6$ = "ip6"
; Phone ?

; See RFC8375
#DNS_DOMAIN_ARPA_HOME$ = "home"
#DNS_DOMAIN_ARPA_HOME_SUBDOMAIN$ = #DNS_DOMAIN_ARPA_HOME$

;}

;- Procedures

; This section contains a couple of useful procedures and the constants that they use.


;
;-> Enumerations & ConstantsProcedures enums & constants
;

; These errors are returned in place of where a pointer should when an error occurs, that's why they go in the negative range.
; A separate pointer could have been given to the procedures to return it, but I personally find them annoying to deal with,
;  and since it is a side project, it doesn't matter all that much as long as it works.
Enumeration DNS_SERVER_PROCEDURES_ERRORS -1 Step -1
	#DNS_ERROR_NULL_INPUT_BUFFER_POINTER
	#DNS_ERROR_NOT_ENOUGH_DATA_HEADER
	#DNS_ERROR_TOO_MUCH_DATA_FOR_UDP
	#DNS_ERROR_MALLOC_FAILURE
	#DNS_ERROR_LIST_INSERT_FAILURE
	#DNS_ERROR_NOT_ENOUGH_DATA_BODY
	
	; You really fucked up if you get these two...
	#DNS_ERROR_NULL_PACKET_POINTER
	#DNS_ERROR_INVALID_SECTION 
	
	#DNS_ERROR_UNKNOWN_OPTION_IN_NAME_FIELD_COMPRESSION ; 01 or 10 instead of 11 !!! - Where is this stated in the RFC ?!!
EndEnumeration

Enumeration DNS_SERVER_PROCEDURES_SECTIONS
	#DNS_SECTION_QUESTIONS
	#DNS_SECTION_ANSWER
	#DNS_SECTION_AUTHORITY
	#DNS_SECTION_ADITIONAL
EndEnumeration


;-> Procedures

; Returns either the new buffer offset if everything went well, or a negative number indicating an error if not.
; A returned value of '0' should never happen !
; INFO: The *QueryBuffer isn't freed in case on an error !
; INFO: The ConcernedSection variable should be one of the values in the DNS_SERVER_PROCEDURES_SECTIONS enum.
; INFO: This procedure assumes that the header has already been parsed and some more small verification steps.
; NOTE: The buffer offset could be given and returned via a pointer to easily pinpoint an error instead of blindly accepting it.
Procedure.i ParseDNSPacketSection(*QueryBuffer, *DNSPacket.DNSPacket, DataAmount.w, BufferOffset.l, ConcernedSection.b,
                                  AssembleNameStrings.b = #True) ;, ParseAdditionalFields.b = #True) ; MUST be derived from ConcernedSection
	
	; This value is a pointer to the current element in the concerned list.
	; It's done this way to avoid using too many 'Select'.
	Protected *ListElement.DNSPacketResourceRecord
	Protected RecordCount.u
	Protected i.i
	
	; Some basic checks
	If Not *QueryBuffer
		ProcedureReturn #DNS_ERROR_NULL_INPUT_BUFFER_POINTER
	EndIf
	
	If Not *DNSPacket
		ProcedureReturn #DNS_ERROR_NULL_PACKET_POINTER
	EndIf
	
	; Getting the record count
	; The value could be used to peek the value and get it faster.
	Select ConcernedSection
		Case #DNS_SECTION_QUESTIONS
			RecordCount = *DNSPacket\Header\QuestionCount
		Case #DNS_SECTION_ANSWER
			RecordCount = *DNSPacket\Header\AnswerCount
		Case #DNS_SECTION_AUTHORITY
			RecordCount = *DNSPacket\Header\AuthorityCount
		Case #DNS_SECTION_ADITIONAL
			RecordCount = *DNSPacket\Header\AditionalRecordsCount
		Default
			; This 'default' check is only done once since more times would be redundant.
			ProcedureReturn #DNS_ERROR_INVALID_SECTION
	EndSelect
	
	; Reading the records from the input buffer
	For i=0 To RecordCount - 1
		; Insures that at least one more byte is available in the buffer (implied)
		If BufferOffset >= DataAmount
			DebuggerWarning("Not enough data remaining... [1]")
			ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_BODY
		EndIf
		
		; Inserting a new element into the correct list and getting the pointer
		Select ConcernedSection
			Case #DNS_SECTION_QUESTIONS
				*ListElement = AddElement(*DNSPacket\QuestionsRecords())
			Case #DNS_SECTION_ANSWER
				*ListElement = AddElement(*DNSPacket\AnswerRecords())
			Case #DNS_SECTION_AUTHORITY
				*ListElement = AddElement(*DNSPacket\AuthorityRecords())
			Case #DNS_SECTION_ADITIONAL
				*ListElement = AddElement(*DNSPacket\AditionalRecords())
		EndSelect
		
		If Not *ListElement
			ProcedureReturn #DNS_ERROR_LIST_INSERT_FAILURE
		EndIf
		
		; Move it to the start of the loop ?
		Protected BytesToRead.a
		
		Repeat
			BytesToRead = PeekA(*QueryBuffer + BufferOffset)
			BufferOffset = BufferOffset + 1
			
			If BytesToRead <> 0
				; Checking if there is enough data to read the string and the next part's size byte
				If (DataAmount - BufferOffset) < BytesToRead + 1
					DebuggerWarning("Not enough data remaining... [2]")
					ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_BODY
				EndIf
				
				If InsertElement(*ListElement\NameParts())
					*ListElement\NameParts() = PeekS(*QueryBuffer + BufferOffset, BytesToRead, #PB_Ascii)
					BufferOffset = BufferOffset + BytesToRead
				Else
					DebuggerWarning("Failed to insert element into list... [1]")
					ProcedureReturn #DNS_ERROR_LIST_INSERT_FAILURE
				EndIf
			EndIf
		Until BytesToRead = 0
		
		; Checking if enough data is left for the 2 remaining common fields ?
		; Not enough data left for the 2 remaining fields ?
		If (DataAmount - BufferOffset) < 4
			DebuggerWarning("Not enough data remaining... [3]")
			ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_BODY
		EndIf
		
		; TODO: Should endianness be swapped here too ???
		
		*ListElement\Type = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		*ListElement\Class = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		; Assembling 'NameParts()' elements into 'Name'
		If AssembleNameStrings
			ForEach *ListElement\NameParts()
				*ListElement\Name = "." + *ListElement\NameParts() + *ListElement\Name
			Next
			*ListElement\Name = Right(*ListElement\Name, Len(*ListElement\Name)-1)
		EndIf
		
		;FIXME: COMPRESSION !!!!!!!
		
		; If more ressources, else next
		If ConcernedSection <> #DNS_SECTION_QUESTIONS
			Debug "FUCK !!!!!!"
			
			; / Checking for TTL and RLENGTH
			If (DataAmount - BufferOffset) < 6
				DebuggerWarning("Not enough data remaining... [4]")
				ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_BODY
			EndIf
			
			; TODO: Should endianness be swapped here too, again ???
			
			*ListElement\TTL = EndianSwapL(PeekL(*QueryBuffer + BufferOffset))
			BufferOffset = BufferOffset + 4
			
			; Add en effective TTL
			
			*ListElement\RDataLength = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
			BufferOffset = BufferOffset + 2
			
			;Verify remaining data size and read the RDATA string
			If *ListElement\RDataLength > (DataAmount - BufferOffset)
				DebuggerWarning("Not enough data remaining... [5]")
				ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_BODY
			EndIf
			
			*ListElement\RData = PeekS(*QueryBuffer + BufferOffset, *ListElement\RDataLength, #PB_Ascii)
			BufferOffset = BufferOffset + *ListElement\RDataLength
		EndIf
	Next
	
	ProcedureReturn BufferOffset
EndProcedure

; Doesn't validate the flags set manually, don't be an idiot !
Procedure EncodeDNSPacketHeaderFlags(*DNSPacket.DNSPacket)
	; Using a separate variable MAY avoid the use of pointers in the final assembly.
	Protected NewFlags.u = $0000
	
	If *DNSPacket
		With *DNSPacket\Header
			NewFlags = NewFlags | ((\Flags\QR & $0001) << 15 )
			NewFlags = NewFlags | ((\Flags\Opcode & $000F) << 11 )
			NewFlags = NewFlags | ((\Flags\AA & $0001) << 10 )
			NewFlags = NewFlags | ((\Flags\TC & $0001) << 9 )
			NewFlags = NewFlags | ((\Flags\RD & $0001) << 8 )
			NewFlags = NewFlags | ((\Flags\RA & $0001) << 7 )
			NewFlags = NewFlags | ((\Flags\Z & $0007) << 4 )
			NewFlags = NewFlags | (\Flags\RCODE & $000F)
			
			; A call to EndianSwapU(...) could be avoided by changing the bit-wise operations.
			; It would also lead to better performances.
			\FlagsWord = EndianSwapU(NewFlags)
		EndWith
		
		ProcedureReturn #True
	EndIf
	
	ProcedureReturn #False
EndProcedure

Procedure DecodeDNSPacketHeaderFlags(*DNSPacket.DNSPacket)
	If *DNSPacket
		With *DNSPacket\Header
			\Flags\QR = (\FlagsWord >> 15) & $0001
			\Flags\Opcode = (\FlagsWord >> 11) & $000F
			\Flags\AA = (\FlagsWord >> 10) & $0001
			\Flags\TC = (\FlagsWord >> 9) & $0001
			\Flags\RD = (\FlagsWord >> 8) & $0001
			\Flags\RA = (\FlagsWord >> 7) & $0001
			\Flags\Z = (\FlagsWord >> 4) & $0007
			\Flags\RCODE = \FlagsWord  & $000F
		EndWith
		
		ProcedureReturn #True
	EndIf
	
	ProcedureReturn #False
EndProcedure



; NOTE: The error code could be returned with a pointer, but it's easier to handle like this.
Procedure.i ParseDNSPacket(*QueryBuffer, DataAmount.w, DecodeHeaderFlags.b = #True, AssembleNameStrings.b = #True)
	Protected *DNSPacket.DNSPacket, BufferOffset.l = 0
	Protected i.i
	
	If Not *QueryBuffer
		ProcedureReturn #DNS_ERROR_NULL_INPUT_BUFFER_POINTER
	EndIf
	
	If DataAmount > #DNS_PACKET_SIZE_MAX_UDP
		ProcedureReturn #DNS_ERROR_TOO_MUCH_DATA_FOR_UDP
	EndIf
	
	If DataAmount < #DNS_HEADER_SIZE
		ProcedureReturn #DNS_ERROR_NOT_ENOUGH_DATA_HEADER
	EndIf
	
	*DNSPacket = AllocateStructure(DNSPacket)
	
	If Not *DNSPacket
		ProcedureReturn #DNS_ERROR_MALLOC_FAILURE
	EndIf
	
	
	; Parsing the header...
	
	With *DNSPacket\Header
		\TransactionID = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		; INFO: Might not need to swap the endianess
		\FlagsWord = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		\FlagsDecoded = DecodeHeaderFlags
		
		If DecodeHeaderFlags
			If Not DecodeDNSPacketHeaderFlags(*DNSPacket)
				; FIXME: Return error
				Debug "Flag decoding error !!!!"
			EndIf
		EndIf
		
		\QuestionCount = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		\AnswerCount = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		\AuthorityCount = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
		
		\AditionalRecordsCount = EndianSwapU(PeekU(*QueryBuffer + BufferOffset))
		BufferOffset = BufferOffset + 2
	EndWith
	
	
	; Reading the different sections...
	
	If *DNSPacket\Header\QuestionCount
		BufferOffset = ParseDNSPacketSection(*QueryBuffer, *DNSPacket, DataAmount, BufferOffset, #DNS_SECTION_QUESTIONS, AssembleNameStrings)
		
		If BufferOffset <= 0
			DebuggerWarning("Question section reading error !")
			FreeStructure(*DNSPacket)
			ProcedureReturn BufferOffset
		EndIf
	EndIf
	
	If *DNSPacket\Header\AnswerCount
		BufferOffset = ParseDNSPacketSection(*QueryBuffer, *DNSPacket, DataAmount, BufferOffset, #DNS_SECTION_ANSWER, AssembleNameStrings)
		
		If BufferOffset <= 0
			DebuggerWarning("Answer section reading error !")
			FreeStructure(*DNSPacket)
			ProcedureReturn BufferOffset
		EndIf
	EndIf
	
	If *DNSPacket\Header\AuthorityCount
		BufferOffset = ParseDNSPacketSection(*QueryBuffer, *DNSPacket, DataAmount, BufferOffset, #DNS_SECTION_AUTHORITY, AssembleNameStrings)
		
		If BufferOffset <= 0
			DebuggerWarning("Authority section reading error !")
			FreeStructure(*DNSPacket)
			ProcedureReturn BufferOffset
		EndIf
	EndIf
	
	If *DNSPacket\Header\AditionalRecordsCount
		BufferOffset = ParseDNSPacketSection(*QueryBuffer, *DNSPacket, DataAmount, BufferOffset, #DNS_SECTION_ADITIONAL, AssembleNameStrings)
		
		If BufferOffset <= 0
			DebuggerWarning("Aditional records section reading error !")
			FreeStructure(*DNSPacket)
			ProcedureReturn BufferOffset
		EndIf
	EndIf
	
	ProcedureReturn *DNSPacket
EndProcedure

; Procedure ProcessQuery(*DNSPacket)
; 	
; EndProcedure
; 
; Procedure SendDNSError(*DNSPacket, ClientID, RCode.u)
; 	
; EndProcedure

Procedure GetDNSBufferSizeForPacket(*DNSPacket.DNSPacket)
	Protected PacketSize = #DNS_HEADER_SIZE
	
	If *DNSPacket
		ForEach *DNSPacket\QuestionsRecords()
			ForEach *DNSPacket\QuestionsRecords()\NameParts()
				PacketSize = PacketSize + StringByteLength(*DNSPacket\QuestionsRecords()\NameParts(), #PB_Ascii) + 1
			Next
			
			PacketSize = PacketSize + 4
		Next
		
		ForEach *DNSPacket\AnswerRecords()
			ForEach *DNSPacket\AnswerRecords()\NameParts()
				PacketSize = PacketSize + StringByteLength(*DNSPacket\AnswerRecords()\NameParts(), #PB_Ascii) + 1
			Next
			
			PacketSize = PacketSize + 4 + 4 + 2 + *DNSPacket\AnswerRecords()\RDataLength
		Next
		
		ForEach *DNSPacket\AuthorityRecords()
			ForEach *DNSPacket\AuthorityRecords()\NameParts()
				PacketSize = PacketSize + StringByteLength(*DNSPacket\AuthorityRecords()\NameParts(), #PB_Ascii) + 1
			Next
			
			PacketSize = PacketSize + 4 + 4 + 2 + *DNSPacket\AuthorityRecords()\RDataLength
		Next
		
		ForEach *DNSPacket\AditionalRecords()
			ForEach *DNSPacket\AditionalRecords()\NameParts()
				PacketSize = PacketSize + StringByteLength(*DNSPacket\AditionalRecords()\NameParts(), #PB_Ascii) + 1
			Next
			
			PacketSize = PacketSize + 4 + 4 + 2 + *DNSPacket\AditionalRecords()\RDataLength
		Next
		
		ProcedureReturn PacketSize
	EndIf
	
	ProcedureReturn 0
EndProcedure

Procedure.i ComposeDNSPacketBufferFromStructure(*DNSPacket.DNSPacket)
	Protected *PacketBuffer, EstimatedPacketSize, BufferOffset.l = 0
	
	If *DNSPacket
		EstimatedPacketSize = GetDNSBufferSizeForPacket(*DNSPacket)
		
		If EstimatedPacketSize > #DNS_PACKET_SIZE_MAX_UDP Or EstimatedPacketSize < #DNS_HEADER_SIZE
			; TODO: Return an error
			Debug "Buffer size invalid: "+EstimatedPacketSize
			ProcedureReturn #Null
		EndIf
		
		Debug "Estimated Packet Size: "+EstimatedPacketSize
		
		*PacketBuffer = AllocateMemory(EstimatedPacketSize)
		
		If Not *PacketBuffer
			ProcedureReturn #DNS_ERROR_MALLOC_FAILURE
		EndIf
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\TransactionID)
		BufferOffset = BufferOffset + 2
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\FlagsWord)
		BufferOffset = BufferOffset + 2
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\QuestionCount)
		BufferOffset = BufferOffset + 2
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\AnswerCount)
		BufferOffset = BufferOffset + 2
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\AuthorityCount)
		BufferOffset = BufferOffset + 2
		
		PokeU(*PacketBuffer + BufferOffset, *DNSPacket\Header\AditionalRecordsCount)
		BufferOffset = BufferOffset + 2
		
		; RR stuff
		; FIXME: TODO !!!!!!
		
	EndIf
	
	ProcedureReturn *PacketBuffer
EndProcedure


;!}

; IDE Options = PureBasic 5.70 LTS (Windows - x64)
; CursorPosition = 668
; FirstLine = 636
; Folding = --
; EnableXP