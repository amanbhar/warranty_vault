# Warranty Vault AI

A full-stack warranty and invoice management platform built with:

* Ruby on Rails API backend
* React + Vite frontend
* PostgreSQL
* Redis + Sidekiq
* Docker-based local development

The system allows users to upload invoices, automatically extract product and warranty information, track warranty expirations, and receive reminders.

---

# 🚀 Features

## Authentication

* Email/password authentication
* Google OAuth login
* JWT-based authorization

---

## Invoice & Warranty Management

* Upload invoices
* OCR text extraction
* AI + rule-based parsing
* Product detection
* Multi-warranty support
* Warranty expiry tracking

---

## Notifications

* In-app notifications
* Warranty reminder scheduling
* Email notifications
* Real-time updates using ActionCable

---

## Frontend Features

* Responsive UI
* Dashboard overview
* Product and invoice management
* Category-based product images

---

# 🏗 Tech Stack

## Frontend

* React (Vite)
* Tailwind CSS
* React Router
* Axios
* ActionCable/WebSocket integration

---

## Backend

* Ruby on Rails API
* PostgreSQL
* Sidekiq
* Redis
* ActionCable
* OmniAuth Google OAuth
* ActiveStorage

---

# 📂 Monorepo Structure

```bash
warranty_vault_ai/
│
├── apps/
│   ├── backend/      # Rails API
│   └── frontend/     # React + Vite frontend
│
├── docker-compose.yml
├── .gitignore
└── README.md
```

---

# ⚙️ Local Development Setup

## 1. Clone Repository

```bash
git clone <repo-url>
cd warranty_vault_ai
```

---

# 🐳 Docker Setup (Recommended)

## Start All Services

```bash
docker compose up --build
```

---

## Services

| Service     | Port                    |
| ----------- | ----------------------- |
| Frontend    | 3006                    |
| Backend API | 3005                    |
| PostgreSQL  | Internal Docker Network |
| Redis       | Internal Docker Network |

---

## Local URLs

Frontend:

```text
http://localhost:3006
```

Backend:

```text
http://localhost:3005
```

Rails Health Check:

```text
http://localhost:3005/up
```

---

# 🔧 Environment Variables

## Backend

Create:

```bash
apps/backend/.env
```

Example:

```env
DATABASE_URL=postgresql://postgres:password@postgres:5432/warranty_vault_development
REDIS_URL=redis://redis:6379/0

JWT_SECRET=your_jwt_secret

FRONTEND_URL=http://localhost:3006
APP_URL=http://localhost:3005

GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=http://localhost:3005/auth/google/callback
```

---

## Frontend

Create:

```bash
apps/frontend/.env
```

Example:

```env
VITE_API_URL=http://localhost:3005
```

---

# 🧠 Application Flow

1. User signs up or logs in
2. User uploads invoice
3. OCR extracts invoice text
4. AI parses structured data
5. Products and warranties are saved
6. Reminder jobs scheduled
7. Notifications delivered

---

# 📌 Important API Endpoints

## Authentication

```http
POST /api/v1/auth/login
GET  /auth/google
```

---

## Invoices

```http
POST /api/v1/invoices/upload
GET  /api/v1/invoices
```

---

## Notifications

```http
GET /api/v1/notifications
```

---

# 🔐 Authentication

JWT authentication is used.

Include token:

```http
Authorization: Bearer <token>
```

---

# 🖼 Product Images

* Local default image system
* Category-based mapping
* No external image APIs required

---

# 📦 Useful Commands

## Start Containers

```bash
docker compose up --build
```

---

## Stop Containers

```bash
docker compose down
```

---

## Rails Console

```bash
docker compose exec backend rails c
```

---

## Run Migrations

```bash
docker compose exec backend rails db:migrate
```

---

## Sidekiq Logs

```bash
docker compose logs -f sidekiq
```

---

# 🚧 Future Improvements

* AWS S3 integration
* Push notifications
* React Native mobile app
* Offline support
* Advanced analytics dashboard
* Production CI/CD pipeline

---

# 🤝 Contributing

Contributions and improvements are welcome.

---

# 📄 License

MIT License
