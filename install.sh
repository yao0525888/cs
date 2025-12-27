#!/bin/bash

# Velyorix License Server 一键安装脚本
# 执行方式: curl -fsSL https://your-domain.com/install.sh | bash
# 或者下载后: chmod +x install.sh && ./install.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查操作系统
check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            PACKAGE_MANAGER="apt-get"

            # 检测具体的发行版
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                case $ID in
                    ubuntu)
                        OS="ubuntu"
                        DOCKER_REPO="ubuntu"
                        ;;
                    debian)
                        OS="debian"
                        DOCKER_REPO="debian"
                        ;;
                    linuxmint|elementary|zorin|pop)
                        # 基于Ubuntu的发行版
                        OS="ubuntu"
                        DOCKER_REPO="ubuntu"
                        ;;
                    raspbian)
                        # 树莓派系统，基于Debian
                        OS="debian"
                        DOCKER_REPO="debian"
                        ;;
                    *)
                        # 未知的基于apt的系统，尝试使用debian仓库
                        log_warn "未知的apt-based系统 $ID，尝试使用Debian配置"
                        OS="debian"
                        DOCKER_REPO="debian"
                        ;;
                esac
            elif [[ -f /etc/debian_version ]]; then
                # 没有os-release但有debian_version的系统
                OS="debian"
                DOCKER_REPO="debian"
            else
                # 最后的回退方案
                log_warn "无法确定具体的Linux发行版，假设为Ubuntu兼容系统"
                OS="ubuntu"
                DOCKER_REPO="ubuntu"
            fi

        elif command -v yum >/dev/null 2>&1; then
            PACKAGE_MANAGER="yum"
            OS="centos"
            DOCKER_REPO="centos"
        elif command -v dnf >/dev/null 2>&1; then
            PACKAGE_MANAGER="dnf"
            OS="fedora"
            DOCKER_REPO="centos"
        else
            log_error "不支持的Linux发行版"
            exit 1
        fi
    else
        log_error "此脚本仅支持Linux系统"
        exit 1
    fi

    log_info "检测到系统: $OS ($ID ${VERSION_ID:-unknown})"
    log_info "包管理器: $PACKAGE_MANAGER"
    log_info "Docker仓库: $DOCKER_REPO"
}

# 安装Docker
install_docker() {
    log_info "检查Docker安装状态..."

    if command -v docker >/dev/null 2>&1; then
        log_success "Docker已安装"
    else
        log_info "安装Docker..."

        # 卸载旧版本
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            sudo $PACKAGE_MANAGER remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true
        fi

        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            # Debian/Ubuntu 安装
            log_info "为 $OS 配置Docker仓库..."

            # 安装依赖
            sudo $PACKAGE_MANAGER update
            sudo $PACKAGE_MANAGER install -y ca-certificates curl gnupg lsb-release wget apt-transport-https

            # 获取系统版本，并处理特殊情况
            SYSTEM_CODENAME=$(lsb_release -cs 2>/dev/null || echo "focal")

            # 处理Debian bookworm的特殊情况
            if [[ "$OS" == "debian" ]] && [[ "$SYSTEM_CODENAME" == "bookworm" ]]; then
                # Debian bookworm可能需要使用bullseye的仓库
                if curl -fsSL --connect-timeout 5 https://download.docker.com/linux/debian/dists/bookworm/Release >/dev/null 2>&1; then
                    log_info "Debian bookworm仓库可用"
                else
                    log_warn "Debian bookworm仓库不可用，尝试使用bullseye仓库"
                    SYSTEM_CODENAME="bullseye"
                fi
            fi

            # 多重回退方案安装Docker
            DOCKER_INSTALLED=false

            # 方案1: 尝试Docker官方仓库
            log_info "方案1: 尝试Docker官方仓库..."
            if curl -fsSL --connect-timeout 10 https://download.docker.com/linux/$DOCKER_REPO/gpg >/dev/null 2>&1; then
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$DOCKER_REPO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_REPO $SYSTEM_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                if sudo $PACKAGE_MANAGER update && sudo $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                    DOCKER_INSTALLED=true
                    log_success "Docker官方仓库安装成功"
                fi
            fi

            # 方案2: 如果官方仓库失败，尝试阿里云镜像
            if [[ "$DOCKER_INSTALLED" == false ]]; then
                log_warn "官方仓库安装失败，尝试阿里云镜像源..."
                sudo rm -f /etc/apt/sources.list.d/docker.list
                sudo mkdir -p /etc/apt/keyrings

                if curl -fsSL --connect-timeout 10 https://mirrors.aliyun.com/docker-ce/linux/$DOCKER_REPO/gpg >/dev/null 2>&1; then
                    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$DOCKER_REPO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$DOCKER_REPO $SYSTEM_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                    if sudo $PACKAGE_MANAGER update && sudo $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                        DOCKER_INSTALLED=true
                        log_success "阿里云镜像源安装成功"
                    fi
                fi
            fi

            # 方案3: 如果还是失败，使用清华大学镜像源
            if [[ "$DOCKER_INSTALLED" == false ]]; then
                log_warn "阿里云镜像源失败，尝试清华大学镜像源..."
                sudo rm -f /etc/apt/sources.list.d/docker.list
                sudo mkdir -p /etc/apt/keyrings

                if curl -fsSL --connect-timeout 10 https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$DOCKER_REPO/gpg >/dev/null 2>&1; then
                    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$DOCKER_REPO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$DOCKER_REPO $SYSTEM_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                    if sudo $PACKAGE_MANAGER update && sudo $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                        DOCKER_INSTALLED=true
                        log_success "清华大学镜像源安装成功"
                    fi
                fi
            fi

            # 方案4: 特殊处理Debian bookworm
            if [[ "$DOCKER_INSTALLED" == false ]] && [[ "$OS" == "debian" ]] && [[ "$(lsb_release -cs 2>/dev/null)" == "bookworm" ]]; then
                log_warn "尝试Debian bookworm专用安装方法..."
                if install_docker_debian_bookworm; then
                    DOCKER_INSTALLED=true
                    log_success "Debian bookworm专用安装成功"
                fi
            fi

            # 方案5: 如果都失败了，使用二进制安装
            if [[ "$DOCKER_INSTALLED" == false ]]; then
                log_warn "所有仓库都失败，使用二进制安装..."
                install_docker_binary
            fi

        elif [[ "$PACKAGE_MANAGER" == "yum" ]] || [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            # CentOS/RHEL/Fedora 安装
            log_info "为 $OS 配置Docker仓库..."

            # 安装依赖
            sudo $PACKAGE_MANAGER install -y yum-utils

            # 添加Docker仓库
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

            # 安装Docker
            sudo $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        fi

        # 启动Docker服务
        sudo systemctl start docker
        sudo systemctl enable docker

        # 添加当前用户到docker组（可选）
        sudo usermod -aG docker $SUDO_USER 2>/dev/null || true

        # 验证安装
        if docker --version >/dev/null 2>&1; then
            log_success "Docker安装完成: $(docker --version)"
        else
            log_error "Docker安装失败"
            exit 1
        fi
    fi
}

# 安装docker-compose
install_docker_compose() {
    log_info "检查Docker Compose安装状态..."

    if docker compose version >/dev/null 2>&1; then
        log_success "Docker Compose V2已安装: $(docker compose version)"
    elif command -v docker-compose >/dev/null 2>&1; then
        log_success "Docker Compose V1已安装: $(docker-compose --version)"
    else
        log_info "安装Docker Compose..."

        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            # Docker Compose V2 已经随docker-ce一起安装了
            log_info "Docker Compose V2 应已随Docker CE一起安装"
        else
            # 其他系统可能需要单独安装
            sudo $PACKAGE_MANAGER install -y docker-compose-plugin
        fi

        # 验证安装
        if docker compose version >/dev/null 2>&1; then
            # Ensure compatibility: create docker-compose wrapper if missing
            if ! command -v docker-compose >/dev/null 2>&1; then
                log_info "创建 docker-compose wrapper -> docker compose"
                sudo tee /usr/local/bin/docker-compose > /dev/null <<'EOF'
#!/bin/bash
exec docker compose "$@"
EOF
                sudo chmod +x /usr/local/bin/docker-compose
                log_success "已创建 /usr/local/bin/docker-compose (wrapper)"
            fi
            log_success "Docker Compose安装完成: $(docker compose version)"
        else
            log_error "Docker Compose安装失败，尝试安装独立版本..."
            # 安装独立版本作为后备方案
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            log_success "Docker Compose独立版本安装完成"
        fi
    fi
}

# 创建项目目录
create_project() {
    log_info "创建Velyorix License Server项目..."

    PROJECT_DIR="/opt/velyorix-license-server"
    sudo mkdir -p $PROJECT_DIR
    sudo chown $USER:$USER $PROJECT_DIR

    cd $PROJECT_DIR

    # 创建目录结构
    mkdir -p api web data

    log_success "项目目录创建完成: $PROJECT_DIR"
}

# 创建Python API服务
create_api_service() {
    log_info "创建API服务..."

    # 创建requirements.txt
    cat > api/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
alembic==1.12.1
pydantic==2.5.0
python-multipart==0.0.6
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
slowapi==0.1.9
aiosqlite==0.19.0
jinja2==3.1.2
aiofiles==23.2.1
EOF

    # 创建数据库模型
    cat > api/models.py << 'EOF'
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, MetaData, create_engine
from sqlalchemy.sql import func
from sqlalchemy.orm import sessionmaker, declarative_base
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./data/velyorix_license.db")

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class ActivationKey(Base):
    __tablename__ = "activation_keys"

    id = Column(Integer, primary_key=True, index=True)
    code_hash = Column(String(128), unique=True, index=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    bound_hwid = Column(String(256), nullable=True)
    status = Column(String(32), nullable=False, default="active")  # active / disabled / expired
    notes = Column(Text, nullable=True)

class AdminUser(Base):
    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(64), unique=True, index=True, nullable=False)
    hashed_password = Column(String(128), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

    # 创建认证模块
    cat > api/auth.py << 'EOF'
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
import os

SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    if password is None:
        password = ""
    # pbkdf2_sha256 不受 72 bytes 限制，直接哈希字符串
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(token: str) -> Optional[str]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            return None
        return username
    except JWTError:
        return None
EOF

    # 创建许可证服务
    cat > api/license_service.py << 'EOF'
import datetime
import secrets
import hmac
import hashlib
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from models import ActivationKey

SERVER_SECRET = "velyorix-server-secret-2024"

def make_code_hash(code: str) -> str:
    digest = hmac.new(SERVER_SECRET.encode("utf-8"), code.encode("utf-8"), hashlib.sha256).hexdigest()
    return digest

def generate_activation_code() -> str:
    return secrets.token_urlsafe(32)

def create_activation_key(db: Session, valid_days: int = 365, notes: Optional[str] = None) -> Tuple[str, Optional[datetime.datetime]]:
    code = generate_activation_code()
    code_hash = make_code_hash(code)
    now = datetime.datetime.utcnow()
    expires_at = now + datetime.timedelta(days=valid_days) if valid_days and valid_days > 0 else None

    db_key = ActivationKey(
        code_hash=code_hash,
        expires_at=expires_at,
        notes=notes,
        status="active"
    )
    db.add(db_key)
    db.commit()
    db.refresh(db_key)

    return code, expires_at

def activate_key(db: Session, code_hash: str, machine_code: str) -> Tuple[bool, str, Optional[datetime.datetime]]:
    key = db.query(ActivationKey).filter(ActivationKey.code_hash == code_hash).first()
    if not key:
        return False, "invalid_code", None

    if key.status != "active":
        return False, "disabled", None

    now = datetime.datetime.utcnow()
    if key.expires_at and key.expires_at < now:
        key.status = "expired"
        db.commit()
        return False, "expired", key.expires_at

    bound_hwid = key.bound_hwid
    if bound_hwid:
        if bound_hwid != machine_code:
            return False, "bound_to_other", key.expires_at
        else:
            return True, "already_bound_same", key.expires_at

    key.bound_hwid = machine_code
    db.commit()
    return True, "bound_now", key.expires_at

def verify_key(db: Session, code_hash: str, machine_code: str) -> Tuple[bool, str, Optional[datetime.datetime], Optional[str]]:
    key = db.query(ActivationKey).filter(ActivationKey.code_hash == code_hash).first()
    if not key:
        return False, "invalid_code", None, None

    if key.status != "active":
        return False, "disabled", key.expires_at, key.bound_hwid

    now = datetime.datetime.utcnow()
    if key.expires_at and key.expires_at < now:
        key.status = "expired"
        db.commit()
        return False, "expired", key.expires_at, key.bound_hwid

    if key.bound_hwid and key.bound_hwid != machine_code:
        return False, "bound_to_other", key.expires_at, key.bound_hwid

    return True, "valid", key.expires_at, key.bound_hwid

def disable_key(db: Session, key_id: int) -> bool:
    key = db.query(ActivationKey).filter(ActivationKey.id == key_id).first()
    if not key:
        return False

    key.status = "disabled"
    db.commit()
    return True

def get_keys_list(db: Session, page: int = 1, per_page: int = 20) -> Tuple[list, int]:
    from sqlalchemy import func as sql_func
    total = db.query(sql_func.count(ActivationKey.id)).scalar()
    keys = db.query(ActivationKey).order_by(ActivationKey.created_at.desc()).offset((page - 1) * per_page).limit(per_page).all()
    return keys, total

def get_key_stats(db: Session) -> dict:
    from sqlalchemy import func as sql_func
    total_keys = db.query(sql_func.count(ActivationKey.id)).scalar()
    active_keys = db.query(sql_func.count(ActivationKey.id)).filter(ActivationKey.status == "active").scalar()
    bound_keys = db.query(sql_func.count(ActivationKey.id)).filter(ActivationKey.bound_hwid.isnot(None)).scalar()
    expired_keys = db.query(sql_func.count(ActivationKey.id)).filter(ActivationKey.status == "expired").scalar()
    disabled_keys = db.query(sql_func.count(ActivationKey.id)).filter(ActivationKey.status == "disabled").scalar()

    return {
        "total_keys": total_keys,
        "active_keys": active_keys,
        "bound_keys": bound_keys,
        "expired_keys": expired_keys,
        "disabled_keys": disabled_keys
    }
EOF

    # 创建主应用
    cat > api/main.py << 'EOF'
import os
import datetime
from fastapi import FastAPI, HTTPException, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
import uvicorn

from models import engine, get_db, Base, AdminUser
from auth import verify_token, get_password_hash, verify_password, create_access_token
from license_service import create_activation_key, activate_key, verify_key, disable_key, get_keys_list, get_key_stats, make_code_hash

# 创建数据库表
Base.metadata.create_all(bind=engine)

# 创建默认管理员用户
def create_default_admin():
    from sqlalchemy.orm import sessionmaker
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()
    try:
        admin = db.query(AdminUser).filter(AdminUser.username == "admin").first()
        if not admin:
            hashed_password = get_password_hash(os.getenv("ADMIN_PASSWORD", "yao581581"))
            admin = AdminUser(
                username="admin",
                hashed_password=hashed_password,
                is_active=True
            )
            db.add(admin)
            db.commit()
            print("Default admin user created: admin/" + os.getenv("ADMIN_PASSWORD", "yao581581"))
    finally:
        db.close()

create_default_admin()

# Rate limiting
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Velyorix License Server", version="1.0.0")

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer(auto_error=False)

# Pydantic models
class LoginRequest(BaseModel):
    username: str
    password: str

class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class CreateKeyRequest(BaseModel):
    valid_days: Optional[int] = 365
    notes: Optional[str] = None

class CreateKeyResponse(BaseModel):
    activation_code: str
    expires_at: Optional[str]

class ActivateRequest(BaseModel):
    activation_code: str
    machine_code: str

class ActivateResponse(BaseModel):
    allowed: bool
    expires_at: Optional[str]
    message: Optional[str]

class VerifyRequest(BaseModel):
    activation_code: str
    machine_code: str

class VerifyResponse(BaseModel):
    valid: bool
    expires_at: Optional[str]
    bound_hwid: Optional[str]
    message: Optional[str]

class KeyInfo(BaseModel):
    id: int
    created_at: str
    expires_at: Optional[str]
    bound_hwid: Optional[str]
    status: str
    notes: Optional[str]

class KeysListResponse(BaseModel):
    keys: List[KeyInfo]
    total: int
    page: int
    per_page: int

class DisableKeyRequest(BaseModel):
    key_id: int

class StatsResponse(BaseModel):
    total_keys: int
    active_keys: int
    bound_keys: int
    expired_keys: int
    disabled_keys: int

# Dependency to get current admin user
async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Token required")

    username = verify_token(credentials.credentials)
    if not username:
        raise HTTPException(status_code=401, detail="Invalid token")

    admin = db.query(AdminUser).filter(AdminUser.username == username, AdminUser.is_active == True).first()
    if not admin:
        raise HTTPException(status_code=401, detail="Admin not found or inactive")

    return admin

# Admin routes
@app.post("/api/admin/login", response_model=LoginResponse)
@limiter.limit("5/minute")
async def admin_login(request: Request, login_data: LoginRequest, db: Session = Depends(get_db)):
    admin = db.query(AdminUser).filter(AdminUser.username == login_data.username).first()
    if not admin or not verify_password(login_data.password, admin.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access_token = create_access_token(data={"sub": admin.username})
    return LoginResponse(access_token=access_token)

@app.post("/api/admin/create_key", response_model=CreateKeyResponse)
async def admin_create_key(req: CreateKeyRequest, admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    code, expires_at = create_activation_key(db=db, valid_days=req.valid_days, notes=req.notes)
    return CreateKeyResponse(activation_code=code, expires_at=expires_at.isoformat() if expires_at else None)

@app.get("/api/admin/keys", response_model=KeysListResponse)
async def admin_get_keys(page: int = 1, per_page: int = 20, admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    keys, total = get_keys_list(db, page, per_page)
    key_infos = []
    for key in keys:
        key_infos.append(KeyInfo(
            id=key.id,
            created_at=key.created_at.isoformat(),
            expires_at=key.expires_at.isoformat() if key.expires_at else None,
            bound_hwid=key.bound_hwid,
            status=key.status,
            notes=key.notes
        ))

    return KeysListResponse(keys=key_infos, total=total, page=page, per_page=per_page)

@app.post("/api/admin/disable_key")
async def admin_disable_key(req: DisableKeyRequest, admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    success = disable_key(db, req.key_id)
    if not success:
        raise HTTPException(status_code=404, detail="Key not found")
    return {"message": "Key disabled successfully"}

@app.get("/api/admin/stats", response_model=StatsResponse)
async def admin_get_stats(admin = Depends(get_current_admin), db: Session = Depends(get_db)):
    stats = get_key_stats(db)
    return StatsResponse(**stats)

# Public license API routes
@app.post("/api/activate", response_model=ActivateResponse)
@limiter.limit("10/minute")
async def license_activate(request: Request, req: ActivateRequest, db: Session = Depends(get_db)):
    client_ip = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    code_hash = make_code_hash(req.activation_code)
    allowed, reason, expires_at = activate_key(db, code_hash, req.machine_code)
    return ActivateResponse(allowed=allowed, expires_at=expires_at.isoformat() if expires_at else None, message=reason)

@app.post("/api/verify", response_model=VerifyResponse)
@limiter.limit("30/minute")
async def license_verify(request: Request, req: VerifyRequest, db: Session = Depends(get_db)):
    client_ip = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    code_hash = make_code_hash(req.activation_code)
    valid, reason, expires_at, bound_hwid = verify_key(db, code_hash, req.machine_code)
    return VerifyResponse(valid=valid, expires_at=expires_at.isoformat() if expires_at else None, bound_hwid=bound_hwid, message=reason)

@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.datetime.utcnow().isoformat()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    log_success "API服务创建完成"
}

# 创建Web管理界面
create_web_interface() {
    log_info "创建Web管理界面..."

    cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Velyorix License Server - 管理后台</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        .sidebar { min-height: 100vh; background: #343a40; }
        .sidebar .nav-link { color: rgba(255,255,255,.75); padding: 0.75rem 1rem; }
        .sidebar .nav-link:hover { color: #fff; background: rgba(255,255,255,.1); }
        .sidebar .nav-link.active { color: #fff; background: #0d6efd; }
        .main-content { padding: 20px; }
        .stats-card { transition: transform 0.2s; }
        .stats-card:hover { transform: translateY(-2px); }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <div class="col-md-3 col-lg-2 px-0 sidebar">
                <div class="d-flex flex-column">
                    <div class="p-3">
                        <h5 class="text-white mb-4"><i class="fas fa-key"></i> Velyorix License</h5>
                        <nav class="nav flex-column">
                            <a class="nav-link active" href="#dashboard" onclick="showSection('dashboard')"><i class="fas fa-tachometer-alt"></i> 控制台</a>
                            <a class="nav-link" href="#create-key" onclick="showSection('create-key')"><i class="fas fa-plus-circle"></i> 生成激活码</a>
                            <a class="nav-link" href="#manage-keys" onclick="showSection('manage-keys')"><i class="fas fa-list"></i> 管理激活码</a>
                        </nav>
                    </div>
                    <div class="mt-auto p-3">
                        <button class="btn btn-outline-light btn-sm w-100" onclick="logout()"><i class="fas fa-sign-out-alt"></i> 退出登录</button>
                    </div>
                </div>
            </div>

            <div class="col-md-9 col-lg-10 px-0">
                <div id="login-section" class="main-content">
                    <div class="row justify-content-center">
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header"><h4><i class="fas fa-lock"></i> 管理员登录</h4></div>
                                <div class="card-body">
                                    <form id="login-form">
                                        <div class="mb-3">
                                            <label class="form-label">用户名</label>
                                            <input type="text" class="form-control" id="username" value="admin" required>
                                        </div>
                                        <div class="mb-3">
                                            <label class="form-label">密码</label>
                                            <input type="password" class="form-control" id="password" value="yao581581" required>
                                        </div>
                                        <button type="submit" class="btn btn-primary w-100"><i class="fas fa-sign-in-alt"></i> 登录</button>
                                    </form>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="dashboard-section" class="main-content" style="display: none;">
                    <h2><i class="fas fa-tachometer-alt"></i> 控制台</h2>
                    <div class="row" id="stats-cards"></div>
                </div>

                <div id="create-key-section" class="main-content" style="display: none;">
                    <h2><i class="fas fa-plus-circle"></i> 生成激活码</h2>
                    <div class="row">
                        <div class="col-md-8">
                            <div class="card">
                                <div class="card-body">
                                    <form id="create-key-form">
                                        <div class="mb-3">
                                            <label class="form-label">有效期（天数）</label>
                                            <select class="form-control" id="valid-days">
                                                <option value="30">30天</option><option value="90">90天</option>
                                                <option value="365" selected>1年</option><option value="730">2年</option>
                                                <option value="0">永久</option>
                                            </select>
                                        </div>
                                        <div class="mb-3">
                                            <label class="form-label">备注</label>
                                            <textarea class="form-control" id="notes" rows="3"></textarea>
                                        </div>
                                        <button type="submit" class="btn btn-success"><i class="fas fa-plus"></i> 生成激活码</button>
                                    </form>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="card">
                                <div class="card-body">
                                    <div id="generated-code" class="alert alert-info" style="display: none;">
                                        <strong>激活码：</strong><br><code id="activation-code" class="fs-6"></code><br><br>
                                        <button class="btn btn-sm btn-outline-primary" onclick="copyToClipboard()"><i class="fas fa-copy"></i> 复制</button>
                                    </div>
                                    <div class="alert alert-warning"><strong>注意：</strong>激活码只会显示一次，请妥善保存！</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div id="manage-keys-section" class="main-content" style="display: none;">
                    <h2><i class="fas fa-list"></i> 管理激活码</h2>
                    <div class="card">
                        <div class="card-body">
                            <div class="table-responsive">
                                <table class="table table-striped" id="keys-table">
                                    <thead><tr>
                                        <th>ID</th><th>创建时间</th><th>过期时间</th><th>绑定机器</th><th>状态</th><th>备注</th><th>操作</th>
                                    </tr></thead>
                                    <tbody id="keys-tbody"></tbody>
                                </table>
                            </div>
                            <nav id="pagination"></nav>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        let currentToken = localStorage.getItem('admin_token');
        let currentPage = 1;

        const API_BASE = window.location.origin;

        document.addEventListener('DOMContentLoaded', function() {
            if (currentToken) {
                showMainInterface();
                loadDashboard();
            } else {
                showLogin();
            }

            document.getElementById('login-form').addEventListener('submit', handleLogin);
            document.getElementById('create-key-form').addEventListener('submit', handleCreateKey);
        });

        function showLogin() {
            document.getElementById('login-section').style.display = 'block';
            document.getElementById('dashboard-section').style.display = 'none';
            document.getElementById('create-key-section').style.display = 'none';
            document.getElementById('manage-keys-section').style.display = 'none';
        }

        function showMainInterface() {
            document.getElementById('login-section').style.display = 'none';
            document.getElementById('dashboard-section').style.display = 'block';
        }

        function showSection(section) {
            if (!currentToken) { showLogin(); return; }
            document.querySelectorAll('.main-content').forEach(el => el.style.display = 'none');
            document.getElementById(section + '-section').style.display = 'block';
            document.querySelectorAll('.sidebar .nav-link').forEach(el => el.classList.remove('active'));
            document.querySelector(`[href="#${section}"]`).classList.add('active');

            if (section === 'dashboard') loadDashboard();
            if (section === 'manage-keys') loadKeys();
        }

        async function handleLogin(e) {
            e.preventDefault();
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;

            try {
                const response = await fetch(`${API_BASE}/api/admin/login`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username, password })
                });

                if (response.ok) {
                    const data = await response.json();
                    currentToken = data.access_token;
                    localStorage.setItem('admin_token', currentToken);
                    showMainInterface();
                    loadDashboard();
                } else {
                    alert('登录失败');
                }
            } catch (error) {
                alert('网络错误');
            }
        }

        function logout() {
            currentToken = null;
            localStorage.removeItem('admin_token');
            showLogin();
        }

        async function loadDashboard() {
            try {
                const response = await fetch(`${API_BASE}/api/admin/stats`, {
                    headers: { 'Authorization': `Bearer ${currentToken}` }
                });

                if (response.ok) {
                    const stats = await response.json();
                    displayStats(stats);
                } else if (response.status === 401) {
                    logout();
                }
            } catch (error) {
                console.error('Error loading dashboard:', error);
            }
        }

        function displayStats(stats) {
            const html = `
                <div class="col-md-3 mb-4">
                    <div class="card stats-card bg-primary text-white">
                        <div class="card-body">
                            <h6>总激活码</h6><h2>${stats.total_keys}</h2>
                        </div>
                    </div>
                </div>
                <div class="col-md-3 mb-4">
                    <div class="card stats-card bg-success text-white">
                        <div class="card-body">
                            <h6>活跃激活码</h6><h2>${stats.active_keys}</h2>
                        </div>
                    </div>
                </div>
                <div class="col-md-3 mb-4">
                    <div class="card stats-card bg-info text-white">
                        <div class="card-body">
                            <h6>已绑定</h6><h2>${stats.bound_keys}</h2>
                        </div>
                    </div>
                </div>
                <div class="col-md-3 mb-4">
                    <div class="card stats-card bg-danger text-white">
                        <div class="card-body">
                            <h6>禁用/过期</h6><h2>${stats.disabled_keys + stats.expired_keys}</h2>
                        </div>
                    </div>
                </div>
            `;
            document.getElementById('stats-cards').innerHTML = html;
        }

        async function handleCreateKey(e) {
            e.preventDefault();
            const validDays = parseInt(document.getElementById('valid-days').value);
            const notes = document.getElementById('notes').value;

            try {
                const response = await fetch(`${API_BASE}/api/admin/create_key`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${currentToken}`
                    },
                    body: JSON.stringify({ valid_days: validDays, notes })
                });

                if (response.ok) {
                    const data = await response.json();
                    document.getElementById('activation-code').textContent = data.activation_code;
                    document.getElementById('generated-code').style.display = 'block';
                    document.getElementById('create-key-form').reset();
                    loadDashboard();
                } else if (response.status === 401) {
                    logout();
                } else {
                    alert('生成失败');
                }
            } catch (error) {
                alert('网络错误');
            }
        }

        function copyToClipboard() {
            const code = document.getElementById('activation-code').textContent;
            navigator.clipboard.writeText(code).then(() => alert('已复制'));
        }

        async function loadKeys(page = 1) {
            currentPage = page;
            try {
                const response = await fetch(`${API_BASE}/api/admin/keys?page=${page}`, {
                    headers: { 'Authorization': `Bearer ${currentToken}` }
                });

                if (response.ok) {
                    const data = await response.json();
                    displayKeys(data);
                } else if (response.status === 401) {
                    logout();
                }
            } catch (error) {
                console.error('Error loading keys:', error);
            }
        }

        function displayKeys(data) {
            const tbody = document.getElementById('keys-tbody');
            tbody.innerHTML = '';

            data.keys.forEach(key => {
                const statusBadge = getStatusBadge(key.status);
                const expiresAt = key.expires_at ? new Date(key.expires_at).toLocaleString() : '永久';
                const createdAt = new Date(key.created_at).toLocaleString();

                const row = `
                    <tr>
                        <td>${key.id}</td>
                        <td>${createdAt}</td>
                        <td>${expiresAt}</td>
                        <td><code>${key.bound_hwid || '-'}</code></td>
                        <td>${statusBadge}</td>
                        <td>${key.notes || '-'}</td>
                        <td>
                            ${key.status === 'active' ? `<button class="btn btn-sm btn-outline-danger" onclick="disableKey(${key.id})">禁用</button>` : '-'}
                        </td>
                    </tr>
                `;
                tbody.innerHTML += row;
            });

            if (data.total > data.per_page) {
                const totalPages = Math.ceil(data.total / data.per_page);
                let pagination = '<ul class="pagination">';
                for (let i = 1; i <= totalPages; i++) {
                    pagination += `<li class="page-item ${i === data.page ? 'active' : ''}"><a class="page-link" href="#" onclick="loadKeys(${i})">${i}</a></li>`;
                }
                pagination += '</ul>';
                document.getElementById('pagination').innerHTML = pagination;
            }
        }

        function getStatusBadge(status) {
            const badges = {
                'active': '<span class="badge bg-success">活跃</span>',
                'disabled': '<span class="badge bg-danger">禁用</span>',
                'expired': '<span class="badge bg-warning">过期</span>'
            };
            return badges[status] || `<span class="badge bg-secondary">${status}</span>`;
        }

        async function disableKey(keyId) {
            if (!confirm('确定禁用这个激活码吗？')) return;

            try {
                const response = await fetch(`${API_BASE}/api/admin/disable_key`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${currentToken}`
                    },
                    body: JSON.stringify({ key_id: keyId })
                });

                if (response.ok) {
                    loadKeys(currentPage);
                    loadDashboard();
                    alert('已禁用');
                } else if (response.status === 401) {
                    logout();
                }
            } catch (error) {
                alert('网络错误');
            }
        }
    </script>
</body>
</html>
EOF

    log_success "Web管理界面创建完成"
}

# 创建Docker配置
create_docker_config() {
    log_info "创建Docker配置..."

    # 创建Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/ .

EXPOSE 8000

CMD ["python", "main.py"]
EOF

    # 创建docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  velyorix-license-server:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./data:/app/data
    restart: unless-stopped
    environment:
      - SECRET_KEY=velyorix-secret-key-2024-production-ready
      - DATABASE_URL=sqlite:///./data/velyorix_license.db
      - ADMIN_PASSWORD=yao581581

  nginx:
    image: nginx:alpine
    ports:
      - "7020:80"
    volumes:
      - ./web:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - velyorix-license-server
    restart: unless-stopped
EOF

    # 创建Nginx配置
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name localhost;

        location /api {
            proxy_pass http://velyorix-license-server:8000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location / {
            root /usr/share/nginx/html;
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF

    log_success "Docker配置创建完成"
}

# 启动服务
start_services() {
    log_info "启动Velyorix License Server..."

    # 启动服务
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d --build
    else
        docker compose up -d --build
    fi

    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10

    # 检查服务状态 (通过 nginx 端口 7020)
    if curl -f http://localhost:7020/api/health >/dev/null 2>&1; then
        log_success "服务启动成功！"
    else
        log_error "服务启动失败，请检查日志：docker-compose logs"
        exit 1
    fi
}

# 显示安装结果
show_installation_info() {
    log_success "🎉 Velyorix License Server 安装完成！"
    echo ""
    echo "📊 访问信息："
    echo "   管理后台: http://$(hostname -I | awk '{print $1}'):7020"
    echo "   API地址: http://$(hostname -I | awk '{print $1}'):7020/api"
    echo ""
    echo "👤 默认管理员账号："
    echo "   用户名: admin"
    echo "   密码: yao581581"
    echo ""
    echo "🔧 管理命令："
    echo "   查看日志: docker-compose logs -f"
    echo "   重启服务: docker-compose restart"
    echo "   停止服务: docker-compose down"
    echo ""
    echo "⚠️  重要提醒："
    echo "   1. 请立即修改默认管理员密码"
    echo "   2. 在生产环境中配置防火墙和HTTPS"
    echo "   3. 定期备份 data/ 目录中的数据库文件"
    echo ""
}

# 旧的主函数已移除，由新的菜单驱动主函数替代

# 检查网络连接
check_network() {
    log_info "检查网络连接..."

    if curl -fsSL --connect-timeout 10 https://www.google.com >/dev/null 2>&1; then
        log_success "网络连接正常"
    elif curl -fsSL --connect-timeout 10 https://www.baidu.com >/dev/null 2>&1; then
        log_success "网络连接正常（国内网络）"
    else
        log_warn "网络连接可能较慢，请耐心等待..."
    fi
}

# 二进制安装Docker（最后的回退方案）
install_docker_binary() {
    log_info "使用二进制方式安装Docker..."

    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cd $TMP_DIR

    # 获取最新版本
    DOCKER_VERSION=$(curl -s https://api.github.com/repos/docker/docker/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')

    if [[ -z "$DOCKER_VERSION" ]]; then
        DOCKER_VERSION="24.0.7"  # 默认版本
    fi

    log_info "下载Docker $DOCKER_VERSION..."

    # 下载Docker二进制文件
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            DOCKER_ARCH="x86_64"
            ;;
        aarch64)
            DOCKER_ARCH="aarch64"
            ;;
        armv7l)
            DOCKER_ARCH="armv7"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            return 1
            ;;
    esac

    # 下载Docker静态二进制文件
    if ! wget -q "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz"; then
        log_error "下载Docker二进制文件失败"
        return 1
    fi

    # 解压并安装
    tar xzvf docker-${DOCKER_VERSION}.tgz
    sudo cp docker/* /usr/bin/
    sudo chmod +x /usr/bin/docker

    # 创建Docker组
    sudo groupadd docker 2>/dev/null || true

    # 创建systemd服务文件
    cat > /tmp/docker.service << 'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    sudo cp /tmp/docker.service /etc/systemd/system/docker.service
    sudo systemctl daemon-reload
    sudo systemctl start docker
    sudo systemctl enable docker

    # 清理临时文件
    cd /
    rm -rf $TMP_DIR

    # 安装Docker Compose二进制文件
    install_docker_compose_binary

    log_success "Docker二进制安装完成"
}

# Debian bookworm专用Docker安装
install_docker_debian_bookworm() {
    log_info "使用Debian bookworm专用安装方法..."

    # 清理之前的配置
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo mkdir -p /etc/apt/keyrings

    # 添加Docker官方GPG密钥
    if ! curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "无法下载Docker GPG密钥"
        return 1
    fi

    # 添加Docker仓库 - 直接使用bookworm
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian bookworm stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 更新包索引
    if ! sudo apt update; then
        log_error "apt update失败"
        return 1
    fi

    # 安装Docker
    if ! sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
        log_error "Docker安装失败"
        return 1
    fi

    return 0
}

# 安装Docker Compose二进制文件
install_docker_compose_binary() {
    log_info "安装Docker Compose..."

    # 获取最新版本
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$COMPOSE_VERSION" ]]; then
        COMPOSE_VERSION="v2.20.0"  # 默认版本
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            COMPOSE_ARCH="x86_64"
            ;;
        aarch64)
            COMPOSE_ARCH="aarch64"
            ;;
        armv7l)
            COMPOSE_ARCH="armv7"
            ;;
        *)
            log_warn "跳过Docker Compose安装：不支持的架构 $ARCH"
            return 0
            ;;
    esac

    # 下载并安装
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    log_success "Docker Compose安装完成"
}

# 应用运行时修复：把生成的模板复制到部署目录，创建 docker-compose wrapper（兼容 docker compose v2），并修复权限
apply_runtime_fixes() {
    log_info "应用运行时修复：复制模板到部署目录并确保 docker-compose 可用"

    PROJECT_DIR="/opt/velyorix-license-server"
    sudo mkdir -p "$PROJECT_DIR"

    # 复制必要文件（覆盖部署目录）
    log_info "复制 api/ web/ docker-compose.yml nginx.conf 到 $PROJECT_DIR"
    # 使用脚本所在目录作为源目录，避免当前工作目录不同导致找不到文件
    SRC_DIR="$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)"
    sudo rm -rf "$PROJECT_DIR"/api "$PROJECT_DIR"/web "$PROJECT_DIR"/Dockerfile "$PROJECT_DIR"/docker-compose.yml "$PROJECT_DIR"/nginx.conf 2>/dev/null || true
    if [[ -d \"$SRC_DIR/api\" ]]; then
        sudo cp -r \"$SRC_DIR/api\" \"$PROJECT_DIR/\" || true
    else
        log_warn \"源目录不存在：$SRC_DIR/api，跳过复制 api/\"
    fi
    if [[ -d \"$SRC_DIR/web\" ]]; then
        sudo cp -r \"$SRC_DIR/web\" \"$PROJECT_DIR/\" || true
    else
        log_warn \"源目录不存在：$SRC_DIR/web，跳过复制 web/\"
    fi
    if [[ -f \"$SRC_DIR/Dockerfile\" ]]; then
        sudo cp \"$SRC_DIR/Dockerfile\" \"$PROJECT_DIR/\" || true
    else
        log_warn \"源文件不存在：$SRC_DIR/Dockerfile，跳过复制 Dockerfile\"
    fi
    if [[ -f \"$SRC_DIR/docker-compose.yml\" ]]; then
        sudo cp \"$SRC_DIR/docker-compose.yml\" \"$PROJECT_DIR/\" || true
    else
        log_warn \"源文件不存在：$SRC_DIR/docker-compose.yml，跳过复制 docker-compose.yml\"
    fi
    if [[ -f \"$SRC_DIR/nginx.conf\" ]]; then
        sudo cp \"$SRC_DIR/nginx.conf\" \"$PROJECT_DIR/\" || true
    else
        log_warn \"源文件不存在：$SRC_DIR/nginx.conf，跳过复制 nginx.conf\"
    fi

    # 设置权限
    OWNER="${SUDO_USER:-$(whoami)}"
    sudo chown -R "$OWNER":"$OWNER" "$PROJECT_DIR"

    # 创建 docker-compose wrapper（如果系统只有 docker compose v2）
    if ! command -v docker-compose >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
        log_info "创建 /usr/local/bin/docker-compose wrapper -> docker compose"
        sudo tee /usr/local/bin/docker-compose > /dev/null <<'EOF'
#!/bin/bash
exec docker compose "$@"
EOF
        sudo chmod +x /usr/local/bin/docker-compose
        log_success "已创建 /usr/local/bin/docker-compose"
    fi

    log_success "运行时修复应用完成"
}

# 显示菜单
show_menu() {
    echo ""
    echo "========================================"
    echo "🚀 Velyorix License Server 管理单"
    echo "========================================"
    echo "1) 完整安装 (推荐新手)"
    echo "2) 仅安装Docker环境"
    echo "3) 查看服务状态"
    echo "4) 启动服务"
    echo "5) 停止服务"
    echo "6) 重启服务"
    echo "7) 查看日志"
    echo "8) 卸载服务"
    echo "9) 退出"
    echo "========================================"
    echo ""
}

# 完整安装流程
full_install() {
    log_info "开始完整安装流程..."

    check_network
    check_os
    install_docker
    install_docker_compose
    create_project
    create_api_service
    create_web_interface
    create_docker_config
    # 在启动服务前把生成的模板复制到部署目录并应用运行时修复（wrapper 等）
    apply_runtime_fixes
    start_services
    show_installation_info

    log_success "完整安装完成！"
}

# 仅安装Docker
install_docker_only() {
    log_info "开始安装Docker环境..."

    check_os
    install_docker
    install_docker_compose

    log_success "Docker环境安装完成！"
    echo ""
    echo "现在你可以运行其他选项来管理服务。"
}

# 查看服务状态
check_service_status() {
    log_info "检查服务状态..."

    if [[ -f "/opt/velyorix-license-server/docker-compose.yml" ]]; then
        cd /opt/velyorix-license-server

        echo "Docker服务状态:"
        sudo systemctl status docker --no-pager -l | head -10

        echo ""
        echo "容器状态:"
        if command -v docker-compose >/dev/null 2>&1; then
            docker-compose ps
        elif docker compose version >/dev/null 2>&1; then
            docker compose ps
        else
            echo "Docker Compose未安装"
        fi

        echo ""
        echo "服务健康检查 (通过端口 7020):"
        if curl -f http://localhost:7020/api/health >/dev/null 2>&1; then
            echo "✅ API服务正常"
        else
            echo "❌ API服务异常"
        fi

        if curl -f http://localhost:7020 >/dev/null 2>&1; then
            echo "✅ Web服务正常"
        else
            echo "❌ Web服务异常"
        fi
    else
        log_error "服务未安装，请先选择选项1进行完整安装"
    fi
}

# 启动服务
start_service() {
    log_info "启动服务..."

    if [[ -f "/opt/velyorix-license-server/docker-compose.yml" ]]; then
        cd /opt/velyorix-license-server

        if command -v docker-compose >/dev/null 2>&1; then
            docker-compose up -d
        else
            docker compose up -d
        fi

        log_success "服务启动完成"
        sleep 3
        check_service_status
    else
        log_error "服务未安装，请先选择选项1进行完整安装"
    fi
}

# 停止服务
stop_service() {
    log_info "停止服务..."

    if [[ -f "/opt/velyorix-license-server/docker-compose.yml" ]]; then
        cd /opt/velyorix-license-server

        if command -v docker-compose >/dev/null 2>&1; then
            docker-compose down
        else
            docker compose down
        fi

        log_success "服务已停止"
    else
        log_error "服务未安装"
    fi
}

# 重启服务
restart_service() {
    log_info "重启服务..."
    stop_service
    sleep 2
    start_service
}

# 查看日志
view_logs() {
    log_info "查看服务日志..."

    if [[ -f "/opt/velyorix-license-server/docker-compose.yml" ]]; then
        cd /opt/velyorix-license-server

        echo "选择要查看的日志:"
        echo "1) API服务日志"
        echo "2) Web服务日志"
        echo "3) 所有服务日志"
        echo "4) 返回菜单"
        read -p "请选择 (1-4): " log_choice

        case $log_choice in
            1)
                if command -v docker-compose >/dev/null 2>&1; then
                    docker-compose logs -f velyorix-license-server
                else
                    docker compose logs -f velyorix-license-server
                fi
                ;;
            2)
                if command -v docker-compose >/dev/null 2>&1; then
                    docker-compose logs -f nginx
                else
                    docker compose logs -f nginx
                fi
                ;;
            3)
                if command -v docker-compose >/dev/null 2>&1; then
                    docker-compose logs -f
                else
                    docker compose logs -f
                fi
                ;;
            4)
                return
                ;;
            *)
                log_error "无效选择"
                ;;
        esac
    else
        log_error "服务未安装"
    fi
}

# 卸载服务
uninstall_service() {
    log_warn "⚠️  卸载将删除所有数据和服务文件！"
    read -p "确定要卸载Velyorix License Server吗？(输入 'yes' 确认): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_info "卸载已取消"
        return
    fi

    log_info "开始卸载服务..."

    # 停止并删除容器
    if [[ -d "/opt/velyorix-license-server" ]]; then
        cd /opt/velyorix-license-server

        if command -v docker-compose >/dev/null 2>&1; then
            docker-compose down -v 2>/dev/null || true
        elif docker compose version >/dev/null 2>&1; then
            docker compose down -v 2>/dev/null || true
        fi
    fi

    # 删除项目目录
    sudo rm -rf /opt/velyorix-license-server

    # 删除Docker镜像（可选）
    read -p "是否删除Docker镜像？(y/N): " delete_images
    if [[ "$delete_images" == "y" ]] || [[ "$delete_images" == "Y" ]]; then
        docker rmi $(docker images -q velyorix-license-server) 2>/dev/null || true
        docker rmi nginx:alpine 2>/dev/null || true
    fi

    log_success "服务卸载完成"
}

# 主函数
main() {
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本：sudo $0"
        exit 1
    fi

    while true; do
        echo "🚀 Velyorix License Server 一键安装脚本"
        echo "========================================"
        show_menu

        read -p "请选择操作 (1-9): " choice

        case $choice in
            1)
                full_install
                ;;
            2)
                install_docker_only
                ;;
            3)
                check_service_status
                ;;
            4)
                start_service
                ;;
            5)
                stop_service
                ;;
            6)
                restart_service
                ;;
            7)
                view_logs
                ;;
            8)
                uninstall_service
                ;;
            9)
                log_info "再见！"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
        clear
    done
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
