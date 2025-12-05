from pydantic import BaseModel, EmailStr, Field


# Login
class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = 'bearer'
    user: dict


# Register (réutilise UserCreate)
# Voir user.py


# Refresh token
class RefreshTokenRequest(BaseModel):
    refresh_token: str


class RefreshTokenResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'


# Réponse erreur
class ErrorResponse(BaseModel):
    detail: str
