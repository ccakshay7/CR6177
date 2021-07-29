CREATE OR REPLACE PROCEDURE ODS_HUB.GETORDERREPLICATIONDET
AS
     --METADATA VARIABLES
  V_STARTTIME TIMESTAMP := SYSTIMESTAMP;
  EXIT_PROCEDURE EXCEPTION;
  V_SP_NAME   VARCHAR2(500 BYTE) := 'GETORDERREPLICATIONDET';
  V_SQL_Exp   VARCHAR2(4000 BYTE);
  V_SP_Params VARCHAR2(4000 BYTE):= NULL;
  V_CheckSERVICEStatus      VARCHAR2(10  CHAR);
  V_ODS_ENGINE_STAUS        VARCHAR2(10  CHAR);
  OUT_STATUS_CODE			VARCHAR2(10 CHAR);
  OUT_STATUS_MSG			VARCHAR2(250 CHAR);
  OUT_RESPONSE   			VARCHAR2(10 CHAR):=NULL;

  V_Cont_Info               CLOB;
  V_Cont_Info1              CLOB;
  V_OUT_OFFERS				CLOB;
  V_CO_ID                   VARCHAR2(50);
  V_MSISDN                  VARCHAR2(50);
  V_CO_CODE                 VARCHAR2(50);
  V_CS_ID                   VARCHAR2(50);
  V_CUST_CODE               VARCHAR2(50);
  V_CUST_TYP				VARCHAR2(5);
  -----------------------------------------
  V_CH_STATUS               VARCHAR2(50);
  V_TMP_STATUS				VARCHAR2(2);
  V_PR_STATUS				VARCHAR2(10);
  v_cnt						NUMBER;
  ------------------Contract------------------
  Cursor orders
  is
  SELECT *
  FROM ODS_HUB.ORDERS_IN_PROGRESS
  WHERE OIP_STATUS='O';

BEGIN
  BEGIN
        --check service configuration to check running status
  SELECT UPPER(STATUS) INTO V_CheckSERVICEStatus FROM ODS_SRV.SERVICE_CONFIG where SERVICE_NAME ='GETORDERREPLICATIONDET';
  SELECT UPPER(STATUS) INTO V_ODS_ENGINE_STAUS FROM ODS_SRV.SERVICE_CONFIG where SERVICE_NAME ='ODS_ENGINE';

  IF (V_ODS_ENGINE_STAUS ='DISABLED')
  THEN
  OUT_STATUS_CODE := 'ODS77777';
  OUT_STATUS_MSG  := 'ODS Service is not available';
  RAISE EXIT_PROCEDURE;
  END IF;

  IF (V_CheckSERVICEStatus ='DISABLED')
  THEN
  OUT_STATUS_CODE := 'ODS77777';
  OUT_STATUS_MSG  := 'ODS Service is not available';
  RAISE EXIT_PROCEDURE;
  END IF;

  FOR i in orders
  LOOP
	
   BEGIN
    ---Check for contract activation replicated from BSCS
	IF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) in ('MOBILE ON-HOLD ACTIVATION',
														'MOBILE ACTIVATION PREPAYMENT',
														'MOBILE ACTIVATION',
														'PORT-IN ORDER',
														'DATA SIM WELCOME PACK')
	THEN
	 BEGIN
	    V_TMP_STATUS:='A';
		V_CH_STATUS:='N';
		
		IF (i.customer_id_new<>nvl(i.custcode,1) and upper(i.order_type) in ('MOBILE ON-HOLD ACTIVATION',
																			 'MOBILE ACTIVATION PREPAYMENT',
																			 'MOBILE ACTIVATION',
																			 'PORT-IN ORDER'))
		THEN 
		update orders_in_progress
		set    custcode=i.customer_id_new
		where dn_num=i.dn_num
		and   oip_id=i.oip_id;
		
		ELSIF (i.customer_id_old<>nvl(i.custcode,1) and Upper(i.order_type) in ('DATA SIM WELCOME PACK'))
		THEN
		update orders_in_progress
		set    custcode=i.customer_id_old
		where dn_num=i.dn_num
		and   oip_id=i.oip_id;		
		
		END IF;
		 
		 SELECT upper(CH_STATUS)
         INTO V_CH_STATUS
         FROM ODS_BSCS.contract_all con,
              (SELECT /*+INDEX (contr_services_cap)*/ co_id
               FROM ODS_BSCS.contr_services_cap cap, ODS_BSCS.directory_number dn
               WHERE cap.dn_id=dn.dn_id 
               and dn_num=i.DN_NUM
			   and cs_deactiv_date IS NULL
               --order by cs_deactiv_date desc nulls first
               fetch first row only) Dn
         WHERE con.co_id=dn.co_id;
		 
		 --IF DATA REPLICATED UPDATE TO 'C'
		 IF V_CH_STATUS=V_TMP_STATUS
		 THEN
		 
		 update ODS_HUB.ORDERS_IN_PROGRESS
		 set   OIP_STATUS='C',
		       RPL_TRX_TYPE='U',
			   RPL_LAST_UPD_DATE=SYSDATE
		 where DN_NUM=i.DN_NUM
		 and   OIP_ID=i.OIP_ID; 
		 
		 END IF;
		 
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found1';
			V_CH_STATUS:='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter1';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception1';
            RAISE EXIT_PROCEDURE;
     END;
	
	---Check for contract deactivation replicated from BSCS	
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) in ('PORT-BACK ORDER','MOBILE MULTI LINE DEACTIVATION','STATUS MODIFICATION')
	THEN 
	 BEGIN
	    V_TMP_STATUS:='D'; 
		V_CH_STATUS:='N';
		
		IF i.customer_id_old<>nvl(i.custcode,1)
		THEN 
		update orders_in_progress
		set    custcode=i.customer_id_old
		where dn_num=i.dn_num
		and   oip_id=i.oip_id;		
		
		END IF;		
	 		 
         SELECT upper(CH_STATUS)
         INTO V_CH_STATUS
         FROM ODS_BSCS.contract_all con,
              (SELECT /*+INDEX (contr_services_cap)*/ co_id
               FROM ODS_BSCS.contr_services_cap cap, ODS_BSCS.directory_number dn
               WHERE cap.dn_id=dn.dn_id 
               and dn_num=i.DN_NUM
			   and cs_deactiv_date IS NOT NULL
               order by cs_deactiv_date desc nulls first
               fetch first row only) Dn
         WHERE con.co_id=Dn.co_id
		 AND   con.CH_STATUS='d';
		 
		 --IF DATA REPLICATED UPDATE TO 'C'
		 IF V_CH_STATUS=V_TMP_STATUS
		 THEN
		 
		 update ODS_HUB.ORDERS_IN_PROGRESS
		 set   OIP_STATUS='C',
		       RPL_TRX_TYPE='U',
			   RPL_LAST_UPD_DATE=SYSDATE
		 where DN_NUM=i.DN_NUM
		 and   OIP_ID=i.OIP_ID;		 
		 
		 END IF;	
		 
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found2';
			V_CH_STATUS:='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter2';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception2';
            RAISE EXIT_PROCEDURE;
     END;
   
    ---Check for customer moved to enterprise replicated from BSCS
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) ='CONS TO ENTERP MIGRATION'--'CONSUMER TO ENTERPRISE'
	THEN 
	 BEGIN	 
		   IF i.customer_id_old<>nvl(i.custcode,1)
		   THEN 
		   update orders_in_progress
		   set    custcode=i.customer_id_old
		   where dn_num=i.dn_num
		   and   oip_id=i.oip_id;		
		   
		   END IF;

           select custcode,cscusttype
		   into   V_CUST_CODE,V_CUST_TYP
		   from   ODS_BSCS.customer_all
		   --where  custcode=i.customer_id_new
		   where  customer_id in (SELECT distinct customer_id
                                  FROM ODS_BSCS.contract_all con,
                                       (SELECT /*+INDEX (contr_services_cap)*/ co_id
                                        FROM ODS_BSCS.contr_services_cap cap, ODS_BSCS.directory_number dn
                                        WHERE cap.dn_id=dn.dn_id 
                                        and dn_num=i.DN_NUM
		                                and cs_deactiv_date IS NULL
                                        order by cs_deactiv_date desc nulls first
                                        fetch first row only) Dn
                                  WHERE con.co_id=dn.co_id);

           IF V_CUST_CODE=i.CUSTOMER_ID_NEW AND V_CUST_TYP not in ('C')
		   THEN			
		      update ODS_HUB.ORDERS_IN_PROGRESS
		      set   OIP_STATUS='C',
		            RPL_TRX_TYPE='U',
		  	        RPL_LAST_UPD_DATE=SYSDATE
		      where DN_NUM=i.DN_NUM
		      and   OIP_ID=i.OIP_ID;

		   END IF;
		   
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found3';
			V_CUST_CODE:=NULL;
			V_CUST_TYP:='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter3';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception3';
            RAISE EXIT_PROCEDURE;
     END;		   

    ---Check for customer moved to consumer segment replicated from BSCS
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) in('ENT2CONS MIGRATION PREPAYMENT','ENTERP TO CONS MIGRATION')--'ENTERPRISE TO CONSUMER'
	THEN 
	 BEGIN
		    IF i.customer_id_new<>nvl(i.custcode,1)
		    THEN 
		    update orders_in_progress
		    set    custcode=i.customer_id_new
		    where dn_num=i.dn_num
		    and   oip_id=i.oip_id;		
		    
		    END IF;
	 
           select custcode,cscusttype
		   into   V_CUST_CODE,V_CUST_TYP
		   from   ODS_BSCS.customer_all
		   --where  custcode=i.customer_id_new;
		   where customer_id in (SELECT distinct customer_id
                                  FROM ODS_BSCS.contract_all con,
                                       (SELECT /*+INDEX (contr_services_cap)*/ co_id
                                        FROM ODS_BSCS.contr_services_cap cap, ODS_BSCS.directory_number dn
                                        WHERE cap.dn_id=dn.dn_id 
                                        and dn_num=i.DN_NUM
		                                and cs_deactiv_date IS NULL
                                        order by cs_deactiv_date desc nulls first
                                        fetch first row only) Dn
                                  WHERE con.co_id=dn.co_id);

           IF V_CUST_CODE=i.CUSTOMER_ID_NEW AND V_CUST_TYP in ('C')
		   THEN			
		      update ODS_HUB.ORDERS_IN_PROGRESS
		      set   OIP_STATUS='C',
		            RPL_TRX_TYPE='U',
		  	        RPL_LAST_UPD_DATE=SYSDATE
		      where DN_NUM=i.DN_NUM
		      and   OIP_ID=i.OIP_ID;

		   END IF;
		   
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found4';
			V_CUST_CODE:=NULL;
			V_CUST_TYP:='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter4';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception4';
            RAISE EXIT_PROCEDURE;
     END;	 
		   
    ---Check for contract assigned with welcome pack replicated from BSCS
	/*ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) ='DATA SIM WELCOME PACK'
	THEN
	
		IF i.customer_id_old<>i.custcode
		THEN 
		update orders_in_progress
		set    custcode=i.customer_id_old
		where dn_num=i.dn_num
		and   oip_id=i.oip_id;		
		
		END IF;*/	
	
	---Check for contract moved to prepaid replicated from BSCS
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) ='POST TO PRE MIGRATION'
	THEN
	 BEGIN
			V_TMP_STATUS:='PR';
			V_PR_STATUS :='N';
			
		    IF i.customer_id_old<>nvl(i.custcode,1)
		    THEN 
		    update orders_in_progress
		    set    custcode=i.customer_id_old
		    where dn_num=i.dn_num
		    and   oip_id=i.oip_id;		
		    
		    END IF;			
	 
		    SELECT  DISTINCT
                    CUSA.CUSTCODE,
                    CASE WHEN RTP.PROVISION_EXT='X'
					     THEN 'PR'
					     ELSE 'PP' END Cont_Type           	     
			INTO    V_CUST_CODE,V_PR_STATUS
            FROM  
                    ODS_BSCS.CONTRACT_ALL          CON,
                    ODS_BSCS.CUSTOMER_ALL          CUSA,
                    ODS_BSCS.RATEPLAN              RTP,
		    		ODS_BSCS.CONTR_SERVICES_CAP    CAP,
		    		ODS_BSCS.DIRECTORY_NUMBER      DN
            WHERE   CUSA.CUSTOMER_ID=CON.CUSTOMER_ID
                AND CON.TMCODE=RTP.TMCODE
		    	AND CON.CO_ID=CAP.CO_ID
		    	AND CAP.DN_ID=DN.DN_ID
		    	AND DN.DN_NUM=i.DN_NUM
				AND CON.CH_STATUS in ('a','s')
		    	AND CUSA.CUSTCODE=i.CUSTOMER_ID_OLD
				AND CAP.cs_deactiv_date IS NULL;
				
           IF V_CUST_CODE=i.CUSTOMER_ID_NEW AND V_PR_STATUS in ('PR')
		   THEN			
		      update ODS_HUB.ORDERS_IN_PROGRESS
		      set   OIP_STATUS='C',
		            RPL_TRX_TYPE='U',
		  	        RPL_LAST_UPD_DATE=SYSDATE
		      where DN_NUM=i.DN_NUM
		      and   OIP_ID=i.OIP_ID;

		   END IF;
		   
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found6';
			V_PR_STATUS :='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter6';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception6';
            RAISE EXIT_PROCEDURE;
     END;     				

	---Check for contract moved to postpaid replicated from BSCS
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) in('PRE2POS MIGRATION PREPAYMENT','PRE TO POST MIGRATION')
	THEN
	 BEGIN
			V_TMP_STATUS:='PP';
			V_PR_STATUS :='N';
			
		    IF i.customer_id_old<>nvl(i.custcode,1)
		    THEN 
		    update orders_in_progress
		    set    custcode=i.customer_id_old
		    where dn_num=i.dn_num
		    and   oip_id=i.oip_id;		
		    
		    END IF;				
	 
		    SELECT  DISTINCT
                    CUSA.CUSTCODE,
                    CASE WHEN RTP.PROVISION_EXT='X' 
					     THEN 'PR'
					     ELSE 'PP' END Cont_Type           	     
			INTO    V_CUST_CODE,V_PR_STATUS
            FROM  
                    ODS_BSCS.CONTRACT_ALL          CON,
                    ODS_BSCS.CUSTOMER_ALL          CUSA,
                    ODS_BSCS.RATEPLAN              RTP,
		    		ODS_BSCS.CONTR_SERVICES_CAP    CAP,
		    		ODS_BSCS.DIRECTORY_NUMBER      DN
            WHERE   CUSA.CUSTOMER_ID=CON.CUSTOMER_ID
                AND CON.TMCODE=RTP.TMCODE
		    	AND CON.CO_ID=CAP.CO_ID
		    	AND CAP.DN_ID=DN.DN_ID
		    	AND DN.DN_NUM=i.DN_NUM
				AND CON.CH_STATUS in ('a','s')
		    	AND CUSA.CUSTCODE=i.CUSTOMER_ID_OLD
				AND CAP.cs_deactiv_date IS NULL;
				
           IF V_CUST_CODE=i.CUSTOMER_ID_NEW AND V_PR_STATUS in ('PP')
		   THEN			
		      update ODS_HUB.ORDERS_IN_PROGRESS
		      set   OIP_STATUS='C',
		            RPL_TRX_TYPE='U',
		  	        RPL_LAST_UPD_DATE=SYSDATE
		      where DN_NUM=i.DN_NUM
		      and   OIP_ID=i.OIP_ID;

		   END IF;
		   
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found7';
			V_PR_STATUS :='N';
            --RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter7';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception7';
            RAISE EXIT_PROCEDURE;
     END;		   

	---Check for contract has change of ownership replicated from BSCS
	ELSIF i.DN_NUM IS NOT NULL AND Upper(i.ORDER_TYPE) in('COO PREPAYMENT','CHANGE OF OWNERSHIP')--'CHANGE OF OWNERSHIP'
	THEN
	 BEGIN
		    update orders_in_progress
		    set    custcode=null
		    where dn_num=i.dn_num
		    and   oip_id=i.oip_id;	 
	 
           select custcode
		   into   V_CUST_CODE
		   from   ODS_BSCS.customer_all
		   where  customer_id in (SELECT distinct customer_id
                                  FROM ODS_BSCS.contract_all con,
                                       (SELECT /*+INDEX (contr_services_cap)*/ co_id
                                        FROM ODS_BSCS.contr_services_cap cap, ODS_BSCS.directory_number dn
                                        WHERE cap.dn_id=dn.dn_id 
                                        and dn_num=i.DN_NUM
		                                and cs_deactiv_date IS NULL
                                        --order by cs_deactiv_date desc nulls first
                                        fetch first row only) Dn
                                  WHERE con.co_id=dn.co_id);

           IF V_CUST_CODE=i.CUSTOMER_ID_NEW
		   THEN			
		      update ODS_HUB.ORDERS_IN_PROGRESS
		      set   OIP_STATUS='C',
		            RPL_TRX_TYPE='U',
		  	        RPL_LAST_UPD_DATE=SYSDATE
		      where DN_NUM=i.DN_NUM
		      and   OIP_ID=i.OIP_ID;
			
		   END IF;
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found8';
			V_CUST_CODE:=null;
            RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter8';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception8';
            RAISE EXIT_PROCEDURE;
     END;		   
	
	END IF;
	
   EXCEPTION
        WHEN NO_DATA_FOUND THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS55555';
            OUT_STATUS_MSG  := 'No Data Found1';
            RAISE EXIT_PROCEDURE;
        WHEN INVALID_NUMBER THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS90003';
            OUT_STATUS_MSG  := 'Invalid Input Parameter1';
            RAISE  EXIT_PROCEDURE;     
        WHEN OTHERS THEN
            V_SQL_Exp := SQLERRM;
            OUT_STATUS_CODE := 'ODS99999';
            OUT_STATUS_MSG  := 'Technical Exception1';
            RAISE EXIT_PROCEDURE;
	
   END;
   END LOOP;
   
   --purge data from main table with beyond 90 days
	BEGIN 
	select count(*)
	into v_cnt
	from ods_hub.orders_in_progress
	where rpl_last_upd_date < sysdate-90;
	
	IF ( v_cnt>0 ) THEN
	
	delete from ods_hub.orders_in_progress where rpl_last_upd_date<sysdate-90 and OIP_STATUS='C';
	COMMIT;
	END IF;
	END;
	
	--purge data from history table with beyond 90 days
	/*BEGIN
	select count(*)
	into v_cnt
	from ods_hub.orders_in_progress_hist 
	where rpl_last_upd_date < sysdate-90;
	
	IF ( v_cnt>0 ) THEN
	
	delete from ods_hub.orders_in_progress_hist where rpl_last_upd_date<sysdate-90;
	COMMIT;
	END IF;
	END;*/
   
   	--commit all transactions
   COMMIT;
   OUT_STATUS_CODE := 'ODS00000';
   OUT_STATUS_MSG  := 'Success Excecution';

  EXCEPTION
    WHEN EXIT_PROCEDURE THEN
      NULL;
    WHEN OTHERS THEN
        V_SQL_EXP:=DBMS_UTILITY.FORMAT_ERROR_BACKTRACE();--SQLERRM;
        OUT_STATUS_CODE := 'ODS99999';
        OUT_STATUS_MSG  := 'Technical Exception';

  END;
    --Debugging

  ADD_DEBUG_INFO(P_REQUEST_ID     => 'Request',
                 P_CORRELATION_ID => 'Request_Corr',
                 P_CHANNEL_NAME   => 'ODS',
                 P_StartTime      => V_StartTime,
                 P_EndTime        => SYSTIMESTAMP(),
                 P_Job_Name       => V_SP_Name,
                 P_Job_Params     => V_SP_Params,
                 P_Job_StepID     => 1,
                 P_STATUS_CODE    => OUT_STATUS_CODE,
                 P_Debug_Msg      => OUT_STATUS_MSG,
                 P_Debug_Details  => V_SQL_EXP,
                 P_RESPONSE_MSG   => OUT_RESPONSE);

END;
/
