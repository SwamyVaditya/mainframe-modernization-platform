       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTBALA.
      ******************************************************************
      * PROGRAM: ACCTBALA - Account Balance Inquiry
      * TYPE:    Batch COBOL + VSAM KSDS
      * DESC:    Production-grade example for portfolio.
      *          Reads ACCTREC copybook, VSAM account file.
      *          Demonstrates DBB dependency resolution.
      * ARCH:    Designed for DBB User Build + zAppBuild 3.14
      * AUTHOR:  Mainframe Modernization Team
      ******************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACCT-FILE ASSIGN TO ACCTFILE
           ORGANIZATION IS INDEXED
           ACCESS MODE IS RANDOM
           RECORD KEY IS ACCT-NUMBER OF ACCT-RECORD
           FILE STATUS IS WS-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD ACCT-FILE.
       COPY ACCTREC.

       WORKING-STORAGE SECTION.
       01 WS-FILE-STATUS        PIC X(02) VALUE '00'.
       01 WS-ACCT-NUMBER        PIC X(10) VALUE '0001234567'.
       01 WS-EOF                PIC X(01) VALUE 'N'.

       PROCEDURE DIVISION.
       MAIN-PARA.
           OPEN INPUT ACCT-FILE
           IF WS-FILE-STATUS NOT = '00'
               DISPLAY 'ACCTBALA: OPEN FAILED ' WS-FILE-STATUS
               MOVE 'Y' TO WS-EOF
           END-IF

           IF WS-EOF = 'N'
               MOVE WS-ACCT-NUMBER TO ACCT-NUMBER OF ACCT-RECORD
               READ ACCT-FILE
               INVALID KEY
                   DISPLAY 'ACCTBALA: ACCOUNT NOT FOUND ' WS-ACCT-NUMBER
               NOT INVALID KEY
                   DISPLAY 'ACCTBALA: BALANCE IS ' ACCT-BALANCE OF
                           ACCT-RECORD
               END-READ
           END-IF

           CLOSE ACCT-FILE
           DISPLAY 'TESTING 1 - CICD WORKFLOWS ... '
           GOBACK.
