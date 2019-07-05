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
;}

;
;- Compiler directives & imports
;{

EnableExplicit

; Already imported elsewhere.
;XIncludeFile "./Endianness.pbi"

XIncludeFile "./Includes/BasicDNS_Core.pbi"

;}


;- Server

;-> Constants

;#SERVER_IP$ = "127.0.0.1" ; Can't capture loopback on windows even with ncap :/ - 'nslookup x.y 192.168.1.250' is used instead.
#SERVER_BUFFER_SIZE = 2048


;-> Code

If InitNetwork() = 0
	MessageRequester("Error", "Can't initialize the network !", 0)
	End
EndIf

Define *Buffer = AllocateMemory(#SERVER_BUFFER_SIZE)

If CreateNetworkServer(0, #DNS_PORT, #PB_Network_UDP | #PB_Network_IPv4);, #SERVER_IP$)
	Debug "Server created (Port "+Str(#DNS_PORT)+")."
	
	Repeat
		Define ServerEvent = NetworkServerEvent()
		
		If ServerEvent = #PB_NetworkEvent_Data
			Debug "Packet received !"
			
			Define ElapsedTime.q, StartTime.q = ElapsedMilliseconds()
			Define ClientID = EventClient()
			Define DataAmount.w, *DNSPacket.DNSPacket
			
			; Cleaning and reading the buffer.
			FillMemory(*Buffer, #SERVER_BUFFER_SIZE)
			DataAmount = ReceiveNetworkData(ClientID, *Buffer, #SERVER_BUFFER_SIZE)
			
			; If no error occured and there is no more data than the server
			;  can handle (2nd cond. shouldn't be false since it's DNS over UDP)
			If DataAmount <> -1 And DataAmount < #SERVER_BUFFER_SIZE
				; Parsing the buffer into a structure
				*DNSPacket = ParseDNSPacket(*Buffer, DataAmount, #True, #True)
				
				If *DNSPacket > 0
					
					Select *DNSPacket\Header\Flags\Opcode
						Case #DNS_OPCODE_QUERY
							Debug "Packet received is a query."
							
							Define Indent.i = 0, FQDN$ = ""
							
							Define Result
							
							; TODO: Check if it is a response
							Result = ProcessQuery(*DNSPacket)
							
							Debug *DNSPacket\QuestionsRecords()\Name
							
							ForEach *DNSPacket\QuestionsRecords()\NameParts()
								Debug Space(Indent * 3) + "└" + *DNSPacket\QuestionsRecords()\NameParts()
								Indent+1
							Next
							
						Case #DNS_OPCODE_IQUERY
							Debug "Packet received is an inverse query."
							; This opcode has been retired by RFC3425
							; It does not indicate which RCODE to return, so "#DNS_RCODE_NOT_IMPLEMENTED" (4) is
							;  returned since it makes sense to do so.
							; The "in-addr.arpa" tree is used instead.
							
							
						Case #DNS_OPCODE_STATUS
							Debug "Packet received is a status request."
							
						Default
							Debug "Packet received is an unknown operation."
							
					EndSelect
					
					FreeStructure(*DNSPacket)
				ElseIf *DNSPacket < 0
					DebuggerWarning("DNS Query parsing error !!!")
					Debug *DNSPacket
					; #DNS_RCODE_FORMAT_ERROR
					
				Else
					DebuggerWarning("Something went terribly wrong, no error code was returned !!!")
					; #DNS_RCODE_SERVER_FAILURE, not really a #DNS_RCODE_FORMAT_ERROR error.
					
				EndIf
			Else
				DebuggerWarning("Data received if either incomplete or too big !")
				; #DNS_RCODE_SERVER_FAILURE
				
			EndIf
			
			; Stopwatch
			ElapsedTime = ElapsedMilliseconds() - StartTime
			If ElapsedTime > 0
				Debug "Took: "+Str(ElapsedTime)+"ms"
			Else
				Debug "Took: <1ms"
			EndIf
			
			Debug ""
			
			; End of #PB_NetworkEvent_Data server event treatement.
		EndIf
	ForEver
	
	CloseNetworkServer(0)
Else
	MessageRequester("Error", "Can't create the server."+#CRLF$+#CRLF$+"Is port "+Str(#DNS_PORT)+" in use ?", 0)
EndIf

; Exit gracefully. - Should never happen !
End 0

; IDE Options = PureBasic 5.70 LTS (Windows - x64)
; CursorPosition = 35
; FirstLine = 15
; Folding = -
; EnableXP
; Executable = DNSTest.exe