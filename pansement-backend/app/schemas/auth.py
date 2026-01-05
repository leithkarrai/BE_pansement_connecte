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


# Change password
class ChangePasswordRequest(BaseModel):
    old_password: str = Field(..., min_length=1, description="Ancien mot de passe")
    new_password: str = Field(..., min_length=12, description="Nouveau mot de passe (minimum 12 caractères)")


# Forgot password
class ForgotPasswordRequest(BaseModel):
    email: EmailStr


# Reset password
class ResetPasswordRequest(BaseModel):
    token: str = Field(..., description="Token de réinitialisation")
    new_password: str = Field(..., min_length=12, description="Nouveau mot de passe (minimum 12 caractères)")


# Verify email
class VerifyEmailRequest(BaseModel):
    token: str = Field(..., description="Token de vérification email")


# Resend verification
class ResendVerificationRequest(BaseModel):
    email: EmailStr


# Réponse erreur
class ErrorResponse(BaseModel):
    detail: str
