; Autor reseni: Frederika Kmeťová xkmeto00

; Projekt 2 - INP 2022
; Vernamova sifra na architekture MIPS64

; DATA SEGMENT
                .data
login:          .asciiz "xkmeto00"  ; sem doplnte vas login
cipher:         .space  17  ; misto pro zapis sifrovaneho loginu

params_sys5:    .space  8   ; misto pro ulozeni adresy pocatku
                            ; retezce pro vypis pomoci syscall 5
                            ; (viz nize "funkce" print_string)
key1: .word 11 ;k 
key2: .word 13 ;m 
over: .word 122 ;overflow
under: .word 96 ;underflow
add_value: .word 26  ;value for additions/substractions 

; CODE SEGMENT
    .text

    ; ZDE NAHRADTE KOD VASIM RESENIM
    ; xkmeto00r1-r2-r5-r28-r0-r4
main:
    while_loop_start:       
    ; first part or first key
        lb r5, login(r1)                  ; load first char 
        slti r28, r5, 97
        bne r28, r0, while_loop_end       ; jump to end 
        lb r2, key1(r0)                   ; load key
        daddu r5, r5, r2                  ; additions
        daddu r28, r5, r0                 ; to r28 save r5 not to rewrite bud to work with 
        lb r2, over(r0)                   ; to r2  overflow
        dsubu r28, r2, r28                ; substract and save it r28
        bgez r28, jump                    ; jump if 
        lb r2, add_value(r0)              ; value that overflows needs to be modified 
        dsubu r5, r5, r2                  ; from r5 substract r2

    jump:
        sb r5, cipher(r1)                 ; save to cipher

        daddi r1, r1, 1                   ; move one char
    ; second part for second key
        lb r5, login(r1)                  ;load second char
        slti r28, r5, 97
        bne r28, r0, while_loop_end       ; jump to end
        lb r2, key2(r0)                   ; load key
        dsubu r5, r5, r2                  ; additions
        daddu r28, r5, r0                 ; to r28 save r5 not to rewrite bud to work with 
        lb r2, under(r0)                  ; to r2  underflow
        dsubu r28, r28, r2                ; substract and save it r28
        bgez r28, jump_2                  ; jump if
        lb r2, add_value(r0)              ; value that underflows needs to be modified 
        daddu r5, r5, r2                  ; from r5 substract r2
        
    jump_2:
        sb r5, cipher(r1)                 ; save to cipher
                         
        daddi r1, r1, 1
        j while_loop_start                ;loop to start again while loop

    while_loop_end:                       ;print
    daddi r4, r0, cipher
    jal print_string
    syscall 0


print_string:   ; adresa retezce se ocekava v r4
    sw      r4, params_sys5(r0)
    daddi   r14, r0, params_sys5    ; adr pro syscall 5 musi do r14
    syscall 5   ; systemova procedura - vypis retezce na terminal
    jr      r31 ; return - r31 je urcen na return address
