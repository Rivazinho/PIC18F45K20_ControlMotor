	LIST p=P18F45K20
	INCLUDE "P18F45K20.INC"
	CONFIG FOSC = INTIO67

	consigna_act equ 0x00
	velocidad_act equ 0x01
	error_act equ 0x02
	suma_error equ 0x03
	suma_comp equ 0x04
	ultimo equ 0x06
	
	convA equ 0x20
	convB equ 0x21
	convC equ 0x22
	dato equ 0x23
	dato1 equ 0x24
	dato2 equ 0x25
 
	ORG 0x00
	goto principal
	ORG 0x08
	goto intAlta
	
;PROGRAMA PRINCIPAL: Configura todos los recursos necesarios y activa las int
principal
	CALL inicializaPorts
	CALL inicializaTMR1
	CALL inicializaTMR3
	CALL inicializaADC
	CALL inicializaPWM
	CALL inicializaUsart
	
	;Configuraci?n de interrupciones del Timer3
	bsf RCON,IPEN,ACCESS
	bsf INTCON,GIEH,ACCESS
	bsf PIR2,TMR3IP,ACCESS
	bcf PIR2, TMR3IF,ACCESS
	bcf PIE2,TMR3IE,ACCESS ;Inicialmente no permito interrupciones a la
	;espera de la se?al de bluetooth

	bra $ ;Bucle en si mismo.

;INTERRUPCIONES prioridad alta, Aqu? se pone el programa	
intAlta
	btfss PIR2, TMR3IF	;Salta si hubo interrupci?n en TMR3
	bra recepcion
	bcf T1CON, TMR1ON	;Detiene contaje
	CALL recargaTMR3
	bcf PIR2, TMR3IF	;Borra flag
	bsf T3CON,TMR3ON	;Arranca
	movff TMR1L,velocidad_act ;Copia el contenido en la variable
	CALL recargaTMR1	;Reinicializa TMR1
	movff ADRESH, consigna_act ;guarda la consigna del CAD
	CALL regulador
	movff suma_error, CCPR2L	;Ajusta ciclo de trabajo de PWM
	movff error_act, LATD  ;Visualiza resultado
	bsf ADCON0,GO		;Arranca cad
	Call preparaPaquete
	retfie
	
recepcion
	btfss PIR1, RCIF ;Salta si es interrupcion por recepci?n
	bra transmision
	;CODIGO DE RECEPCION
	movlw D'83'	;Si es S (set), habilita tmr3 y por lo tanto arranca
	CPFSEQ RCREG 
	bra noEsSet
	
	;Recarga TMR3 y vuelve habilitar la interrupcion
	CALL recargaTMR3
	bsf PIE2,TMR3IE,ACCESS
	retfie
noEsSet
	movlw D'82'	;Si es R(reset), desactiva el motor
	cpfseq RCREG
	bra transmision
	;Deshabilita la interrupcion de TMR3 y para el Motor y borra los leds
	bcf PIR2, TMR3IF,ACCESS
	bcf PIE2,TMR3IE,ACCESS
	movlw 0x00
	movwf CCPR2L
	movwf LATD
	movwf suma_error
	retfie
	
transmision
	;CODIGO DE TRANSMISION
	;Primer byte ya se envi? porque se hizo tras el call preparapaquete
	;Se sigue con los siguientes
	;Compruebo que se haya vaciado el registro desplazamiento
	btfss PIR1, TXIF                
	retfie
	;btfsc ultimo, 0
	;bra final     
	INCF FSR0L  	;avanzo el puntero una posici?n
	movff INDF0, TXREG   ;Cargo el siguiente valor del buffer a trasmitir

	movlw D'42'
	CPFSEQ INDF0 ;Si el valor apuntado es *, se indica que es el ultimo
	retfie      
	;bsf ultimo,0
	bcf PIE1, TXIE
	retfie
final
	;bcf ultimo,0
	;bcf PIE1, TXIE


;retfie   
	
	
fin
	retfie
	
	
	
	
;SUBRUTINAS DE INICIALIZACI?N
	
	
inicializaPorts
	bsf TRISA,0		;RA0 como entrada
	bsf ANSEL,AN0		;RA0 como entrada anal?gica
iniPortD
	clrf TRISD		;RD configurado como salida
	clrf PORTD		;RD a 0
	return
	
inicializaTMR3
	movlw B'10010000'	;Divisor de 2, oscilador interno, no arranque
	movwf T3CON		;Carga la configuracion
	CALL recargaTMR3
	bcf PIR2,TMR3IF		;Borramos el flag de la interrupci?n del timer
	bsf T3CON,TMR3ON	;lanza temporizador
	return

recargaTMR3
	movlw 0x0B
	movwf TMR3H
	movlw 0xDC
	movwf TMR3L
	return

	
inicializaADC
	movlw B'00000001'	;Selecciona RA0 como la entrada u da permiso de 
				;conversi?n
	movwf ADCON0
	movlw B'00101111'	;12*Tad (101), Frc(111) y el bit7 a 0 pq Justi-
				;ficaci?n Izquierda
	movwf ADCON2
	clrf ADCON1		;Tensi?n referencia negativa Vss y positiva Vdd 
				;para la conversion
	return

;************************************************************
;Subrutina de inicializacion del PWM
;PWM_periodo = (PR2+1)*4*Tosc*preescalado_TMR2
;PWM resolucion=log(4^(PR2+1))/log2=3/0.3 = 10 bits
inicializaPWM
	bcf TRISC, 1, 0 ;RC1 como salida => CCP2
	
	clrf CCP2CON, ACCESS	;Inicializa a 0 reg control PWM
	bsf CCP2CON, CCP2M3, ACCESS ;Se establece el modo PWM de la unidad CCP
	bsf CCP2CON, CCP2M2, ACCESS ;CCP2CON<3:0>='11xx'
	
	bsf T2CON, T2CKPS0, ACCESS  ;preescalado de 4 para el timer 2
	bcf T2CON, T2CKPS1, ACCESS  
	movlw 0xFF		    ;PWM_periodo=(PR2+1)*4*Tosc*preescalado_TMR2
				    ;=(255+1)*4*1E-6*4=4096 us = 4 ms => 244 Hz
	movwf PR2, ACCESS
	bsf T2CON, TMR2ON, ACCESS
	return
	 
;inicializa el TMR1 como contador
inicializaTMR1
	bsf TRISC,0	    ;COnfigura RC0 como entrada, para contaje
	movlw B'00000010'
	movwf T1CON,ACCESS  ;Carga la config, flanco en RC0, prescale de 1
recargaTMR1
	movlw 0x00
	movwf TMR1H, ACCESS
	movwf TMR1L, ACCESS ;Pone TMR1 a 0
	bsf T1CON,0	    ;Habilita Contaje
	return
	
;Inicializa el periferico de comunicaciones
inicializaUsart
	;Configurar a 9600 baud (9615 en realidad)
        movlw 0x19 ;25 en hex
	movwf SPBRG
	bsf BAUDCON, BRG16
	bsf TXSTA, BRGH

	;Puertos de comunicaci?n usart RX y TX.
	bsf TRISC,6
	bsf TRISC,7
	bcf TXSTA, SYNC ;Modo as?ncrono UART
	bsf IPR1,RCIP   ;como alta prioridad
	bsf RCSTA, SPEN	;Permiso de funcionamiento del puerto serie
	bsf PIE1, RCIE	;Activo interrupci?n de recepci?n
	bsf TXSTA, TXEN ;Habilito trasmisi?n datos
	bsf RCSTA, CREN ;Habilita recepcion datos
	bcf RCSTA, RX9  ;8 bits  , no uso el noveno    
	bcf BAUDCON, CKTXP ;Polaridad, un 0 es 0v

	return
    
;Subrutina de regulador PI
regulador
	movlw 0x00
	cpfsgt consigna_act ;salta si consigna_act>0
	bra lab0	    ;primera comparacion
	
	movf velocidad_act, 0
	cpfsgt consigna_act ;salta si consigna_act>0
	bra lab1	    ;segunda comparacion
	
	movf velocidad_act, 0
	subwf consigna_act,0,ACCESS ;consigna_act-velocidad_act
	movwf error_act		    ;error_act = resultado
	
	;esto se hace por si el error se pasa de 255, se limita a 255
	comf suma_error,0	;carga en wreg suma error invertida
	movwf suma_comp		;la guarda
	movf error_act,0	;carga error act
	cpfsgt suma_comp	;salta si error comp > error_act
	bra lab2
	
	movf error_act, 0
	addwf suma_error,1  ;suma error_act con suma error y lo guarda en si
	return
	
lab2
	movlw 0xFF	
	movwf suma_error    ;asigna a suma_error el valor FF
	return

lab1
	movf consigna_act,0
	subwf velocidad_act,0	;vel_act-consigna
	movwf error_act		;-->error_act
	movf error_act,0
	cpfsgt suma_error	;salta si sum_er>error_act
	bra lab0
	
	movf error_act, 0
	subwf suma_error, 1	;suma = suma + error
	return

lab0
	movlw 0x00
	movwf suma_error
	return
	
;SUBRUTINA QUE PREPARA LOS PAQUETES PARA ENVIAR
;Prepara el buffer en las direcciones desde 0x30
preparaPaquete
	;Prepara la velocidad
	movff velocidad_act, dato
	CALL binario_BCD
	;Cabecera	
	movlw D'42' ;Asterisco
	movwf 0x30
	movlw D'71' ;Carga una G de gr?fico
	movwf 0x31
	;Dato
	movff convA, 0x32
	movff convB, 0x33
	movff convC, 0x34
	;Separa con una coma, para separar dos datos en el bt
	movlw D'44'
	movwf 0x35
	;Prepara la consigna
	movff consigna_act, dato
	CALL binario_BCD
	;Copia la consigna
	movff convA, 0x36
	movff convB, 0x37
	movff convC, 0x38
	;Byte cierre
	movlw D'42'
	movwf 0x39
	
	;Inicializo como puntero el FSR0
	
	movlw 0x30   	;Primera posici?n del paquete
	movwf FSR0L


	;se carga primer byte en reg de salida
	movff INDF0, TXREG            			    

	;Habilito int salida para recargar
	bsf PIE1, TXIE  
	return
	
;SUBRUTINA CONVERSION BINARIO A BCD
binario_BCD
	movlw 0x00
	movwf convA
	movlw 0x00
	movwf convB
	movlw 0x00
	movwf convC

	movff dato, dato1


lazo1
	movff dato1, dato2

	movlw 0x64	    ;resta 100
	subwf dato1,f               

	movf dato2, w
	CPFSLT dato1                ;dato1<dato2? Ya es menor que 100
	bra lazo12

	movlw 0x01
	ADDWF convA,f
	bra lazo1

lazo12
        movff dato1, dato2

	movlw 0x64
        ADDWF dato1,f
lazo2
        movlw 0x0A
	subwf dato1,f

	movf dato2, w
	cpfslt dato1
	bra lazo3

	movlw 0x01
	addwf convB,f
	bra lazo2

lazo3
	movlw 0x0A
	ADDWF dato1, f

	movff dato1, convC

;Sumarle 0x30h (48 en decimal) al BCD es la conversi?n a ASCII
	movlw 0x30
	ADDWF convC, f

	movlw 0x30
	ADDWF convB, f

	movlw 0x30
	ADDWF convA, f
	return
	
	end