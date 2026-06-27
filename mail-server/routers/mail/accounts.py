from fastapi import APIRouter, Depends, HTTPException
from config import settings, db
from routers.login.auth import verify_token
from util.crypto import encrypt_password, decrypt_password
from schemas.mail.accounts import AccountCreateRequest, AccountUpdateRequest, AccountGetRequest
from .helper.basic_helper import test_imap_connection, test_smtp_connection
import LogAssist.log as logger
import os

SECRET_KEY = settings.SECRET_KEY

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

@router.get("/get_accounts", dependencies=[Depends(verify_token)])
async def get_accounts(account: AccountGetRequest = Depends()):
    account_data = account.model_dump()
    data = {"user_uuid": account_data['user_uuid']}

    return db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "accounts.get_accounts"), 
        data
    )


@router.post("/insert_account", dependencies=[Depends(verify_token)])
async def insert_account(account: AccountCreateRequest):
    account_data = account.model_dump()
    
    # 비밀번호 암호화
    user_uuid = account_data['user_uuid']
    logger.debug("user_uuid", user_uuid)
    logger.debug("SECRET_KEY", SECRET_KEY)

    encrypted_imap_pw = encrypt_password(SECRET_KEY, user_uuid, account_data['imap_password'])
    encrypted_smtp_pw = encrypt_password(SECRET_KEY, user_uuid, account_data['smtp_password'])
    
    query = sqloader.load_sql("mail_anchor.json", "accounts.insert_account")
    data = {
        "user_uuid": user_uuid,
        "account_name": account_data['account_name'],
        "email": account_data['email'],
        "imap_host": account_data['imap_host'],
        "imap_port": account_data['imap_port'],
        "imap_use_ssl": account_data['imap_use_ssl'],
        "imap_username": account_data['imap_username'],
        "imap_password_encrypted": encrypted_imap_pw,
        "smtp_host": account_data['smtp_host'],
        "smtp_port": account_data['smtp_port'],
        "smtp_use_tls": account_data['smtp_use_tls'],
        "smtp_username": account_data['smtp_username'],
        "smtp_password_encrypted": encrypted_smtp_pw,
        "display_color": account_data.get('display_color', '#4285f4')
    }
    return db_instance.execute_query(query, data)


@router.put("/update_account", dependencies=[Depends(verify_token)])
async def update_account(account: AccountUpdateRequest):
    account_data = account.model_dump()
    
    # 비밀번호가 있으면 암호화
    user_uuid = account_data['user_uuid']
    data = {
        "account_uuid": account_data['account_uuid'],
        "user_uuid": user_uuid
    }
    
    if account_data.get('account_name'):
        data['account_name'] = account_data['account_name']
    
    if account_data.get('imap_password'):
        data['imap_password_encrypted'] = encrypt_password(
            SECRET_KEY, user_uuid, account_data['imap_password']
        )
    
    if account_data.get('smtp_password'):
        data['smtp_password_encrypted'] = encrypt_password(
            SECRET_KEY, user_uuid, account_data['smtp_password']
        )
    
    if account_data.get('display_color'):
        data['display_color'] = account_data['display_color']
    
    if account_data.get('sync_enabled') is not None:
        data['sync_enabled'] = account_data['sync_enabled']
    
    query = sqloader.load_sql("mail_anchor.json", "accounts.update_account")
    return db_instance.execute_query(query, data)


@router.delete("/remove_account/{account_uuid}", dependencies=[Depends(verify_token)])
async def remove_account(account_uuid: str):
    query = sqloader.load_sql("mail_anchor.json", "accounts.remove_account")
    return db_instance.execute_query(query, {"account_uuid": account_uuid})


@router.post("/test_connection", dependencies=[Depends(verify_token)])
async def test_connection(account: AccountCreateRequest):
    account_data = account.model_dump()
    logger.debug(account_data)
    
    # IMAP 테스트
    imap_result = test_imap_connection(
        account_data['imap_host'],
        account_data['imap_port'],
        account_data['imap_username'],
        account_data['imap_password'],
        account_data['imap_use_ssl']
    )
    
    # SMTP 테스트
    smtp_result = test_smtp_connection(
        account_data['smtp_host'],
        account_data['smtp_port'],
        account_data['smtp_username'],
        account_data['smtp_password'],
    )
    
    return {
        "imap": imap_result,
        "smtp": smtp_result
    }