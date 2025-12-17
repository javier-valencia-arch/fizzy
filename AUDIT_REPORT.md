# Informe de Auditoría de Seguridad - Fizzy

**Fecha:** 17 de diciembre de 2025  
**Auditor:** Sistema Automatizado de Análisis de Seguridad  
**Versión de la Aplicación:** Rails 8.2.0-alpha

## Resumen Ejecutivo

Este informe presenta los resultados de una auditoría de seguridad integral de la aplicación Fizzy, una herramienta de gestión de proyectos tipo Kanban desarrollada por 37signals/Basecamp. La auditoría se enfocó en identificar vulnerabilidades de seguridad, problemas de configuración, y oportunidades de mejora en la arquitectura y las prácticas de desarrollo.

### Hallazgos Principales

- ✅ **Fortalezas:** La aplicación cuenta con protección CSRF, autenticación sin contraseña (magic links), CSP configurado, rate limiting en endpoints críticos, y auditorías de seguridad automatizadas (Brakeman, Bundler Audit, Gitleaks).

- ⚠️ **Áreas de Mejora:** Falta de configuración de Permissions Policy, validaciones limitadas en modelos, ausencia de sistema de respaldo documentado, logging insuficiente para auditoría, y falta de monitoreo de errores en producción.

---

## Lista de Acciones Prioritarias (de Más Urgente a Menos Urgente)

### 1. 🔴 URGENTE: Implementar Monitoreo de Errores en Producción

**Prioridad:** CRÍTICA  
**Riesgo:** ALTO  
**Esfuerzo:** MEDIO

**Problema:**
- No hay evidencia de integración con servicios de monitoreo de errores (Sentry, Honeybadger, etc.)
- El nivel de log en producción está configurado en `:fatal` (config/environments/production.rb línea 80), lo que oculta errores importantes
- No hay manejo centralizado de excepciones en ApplicationController

**Impacto:**
- Errores críticos en producción pueden pasar desapercibidos
- Dificulta la detección temprana de problemas de seguridad
- Imposibilita el análisis de patrones de fallas

**Solución Recomendada:**
```ruby
# Agregar a Gemfile
gem "sentry-ruby"
gem "sentry-rails"

# Configurar en config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 0.1
  config.enabled_environments = %w[production staging]
end

# Cambiar config/environments/production.rb línea 80
config.log_level = ENV.fetch("LOG_LEVEL", "info").to_sym
```

---

### 2. 🔴 URGENTE: Habilitar y Configurar Permissions Policy

**Prioridad:** ALTA  
**Riesgo:** MEDIO-ALTO  
**Esfuerzo:** BAJO

**Problema:**
- El archivo `config/initializers/permissions_policy.rb` está completamente comentado
- No hay restricciones de acceso a funcionalidades del navegador (cámara, micrófono, geolocalización, etc.)
- Posible vector de ataque mediante iframes maliciosos

**Impacto:**
- Aplicaciones de terceros embebidas podrían acceder a funcionalidades sensibles del navegador
- Mayor superficie de ataque para clickjacking y otras técnicas

**Solución Recomendada:**
```ruby
# Descomentar y configurar config/initializers/permissions_policy.rb
Rails.application.config.permissions_policy do |policy|
  policy.camera      :none
  policy.gyroscope   :none
  policy.microphone  :none
  policy.usb         :none
  policy.fullscreen  :self
  policy.geolocation :none
  policy.payment     :none
end
```

---

### 3. 🟠 ALTA: Resolver Advertencias de Brakeman Ignoradas

**Prioridad:** ALTA  
**Riesgo:** MEDIO  
**Esfuerzo:** MEDIO

**Problema:**
- Existen 4 advertencias de seguridad ignoradas en `config/brakeman.ignore`:
  1. **Dangerous Send** en Events::DayTimeline::ColumnsController (línea 19) - High confidence
  2. **Mass Assignment** en PaginationHelper (línea 14) - Medium confidence
  3. **Remote Code Execution (Unsafe Reflection)** en Notifier (línea 8) - Medium confidence
  4. **SQL Injection** (2 instancias) en Card::Entropic (líneas 10 y 19) - Weak confidence

**Impacto:**
- El uso de `params[:id]` en `public_send` permite ejecución de métodos arbitrarios
- `params.permit!` en PaginationHelper permite mass assignment sin restricciones
- `safe_constantize` basado en atributos de modelo puede permitir RCE

**Solución Recomendada:**
```ruby
# En Events::DayTimeline::ColumnsController línea 19
# ANTES:
Current.user.timeline_for(day, :filter => filter).public_send("#{params[:id]}_column")

# DESPUÉS:
ALLOWED_COLUMNS = %w[added updated].freeze
column_name = params[:id]
raise ArgumentError unless ALLOWED_COLUMNS.include?(column_name)
Current.user.timeline_for(day, :filter => filter).public_send("#{column_name}_column")

# En PaginationHelper línea 14
# Reemplazar params.permit! con lista explícita de parámetros permitidos
params.permit(:page, :per_page, :sort, :direction, :filter_id)

# En Notifier línea 8
# ANTES:
"Notifier::#{Event.eventable.class}EventNotifier".safe_constantize

# DESPUÉS:
ALLOWED_NOTIFIERS = %w[Card Comment Board User].freeze
eventable_type = Event.eventable.class.name
raise ArgumentError unless ALLOWED_NOTIFIERS.include?(eventable_type)
"Notifier::#{eventable_type}EventNotifier".safe_constantize
```

---

### 4. 🟠 ALTA: Implementar Sistema de Respaldos Automatizados

**Prioridad:** ALTA  
**Riesgo:** ALTO  
**Esfuerzo:** MEDIO

**Problema:**
- No hay evidencia de scripts de respaldo en el repositorio
- No hay documentación de estrategia de backup/restore
- La configuración de Kamal define volúmenes persistentes pero no menciona backups
- SQLite en producción requiere estrategia de respaldo cuidadosa

**Impacto:**
- Pérdida de datos en caso de fallo del servidor
- Imposibilidad de recuperación ante desastres
- Incumplimiento potencial de regulaciones de protección de datos

**Solución Recomendada:**
```ruby
# Crear lib/tasks/backup.rake
namespace :backup do
  desc "Backup database and uploaded files"
  task full: :environment do
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_dir = Rails.root.join("tmp", "backups", timestamp)
    FileUtils.mkdir_p(backup_dir)
    
    # Backup database
    db_file = Rails.root.join("storage", "production.sqlite3")
    FileUtils.cp(db_file, backup_dir.join("database.sqlite3"))
    
    # Backup Active Storage files
    storage_dir = Rails.root.join("storage")
    system("tar -czf #{backup_dir}/storage.tar.gz -C #{storage_dir} .")
    
    # Upload to S3 or backup service
    # Implementation depends on backup strategy
  end
end

# Agregar a config/recurring.yml
backup_database:
  schedule: "0 2 * * *" # Daily at 2 AM
  class: BackupJob
```

---

### 5. 🟡 MEDIA: Mejorar Logging y Auditoría

**Prioridad:** MEDIA  
**Riesgo:** MEDIO  
**Esfuerzo:** BAJO

**Problema:**
- Solo 2 instancias de `Rails.logger` en todos los modelos
- No hay logging estructurado de acciones sensibles (cambio de permisos, eliminaciones, etc.)
- El modelo `Event` registra acciones pero no incluye información de auditoría como IP, user agent, etc.

**Impacto:**
- Dificultad para investigar incidentes de seguridad
- Imposibilidad de cumplir con requisitos de auditoría
- Falta de trazabilidad de acciones administrativas

**Solución Recomendada:**
```ruby
# Agregar concern para auditoría
module Auditable
  extend ActiveSupport::Concern
  
  included do
    after_create :log_creation
    after_update :log_update
    after_destroy :log_destruction
  end
  
  private
  
  def log_creation
    Rails.logger.info({
      action: "#{self.class.name.downcase}_created",
      resource_id: id,
      user_id: Current.user&.id,
      account_id: Current.account&.id,
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent
    }.to_json)
  end
  
  # Similar para log_update y log_destruction
end

# Incluir en modelos sensibles como User, Access, Webhook
```

---

### 6. 🟡 MEDIA: Fortalecer Validaciones de Modelos

**Prioridad:** MEDIA  
**Riesgo:** BAJO-MEDIO  
**Esfuerzo:** MEDIO

**Problema:**
- Solo 22 instancias de `validates` en 148 archivos de modelos (15% aproximadamente)
- Muchos modelos carecen de validaciones básicas de presencia, formato y longitud
- Riesgo de datos inconsistentes en la base de datos

**Impacto:**
- Datos corruptos o malformados en la base de datos
- Potencial para inyección de contenido malicioso
- Dificultad en el mantenimiento y debugging

**Solución Recomendada:**
```ruby
# Auditar cada modelo y agregar validaciones apropiadas
class Card < ApplicationRecord
  validates :title, presence: true, length: { maximum: 500 }
  validates :number, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: %w[active closed not_now] }
  # etc.
end

# Crear rake task para detectar modelos sin validaciones
namespace :audit do
  desc "Find models without validations"
  task models_without_validations: :environment do
    # Implementation
  end
end
```

---

### 7. 🟡 MEDIA: Implementar Política de Seguridad de Dependencias

**Prioridad:** MEDIA  
**Riesgo:** MEDIO  
**Esfuerzo:** BAJO

**Problema:**
- Rails está configurado para usar la rama `main` (versión en desarrollo) en lugar de una release estable
- `insecure-external-code-execution: allow` en Dependabot (línea 15 de .github/dependabot.yml)
- No hay política documentada para actualización de dependencias críticas

**Impacto:**
- Inestabilidad por uso de versiones no estables de Rails
- Riesgo de ejecución de código malicioso durante instalación de gems
- Ventana de exposición amplia ante vulnerabilidades conocidas

**Solución Recomendada:**
```ruby
# Cambiar Gemfile para usar versión estable de Rails
gem "rails", "~> 8.0.0" # En lugar de github: "rails/rails", branch: "main"

# Cambiar .github/dependabot.yml
insecure-external-code-execution: deny

# Crear SECURITY_POLICY.md
## Security Update Policy
1. Critical vulnerabilities: Patch within 24 hours
2. High severity: Patch within 7 days
3. Medium severity: Patch within 30 days
4. Weekly dependency review
```

---

### 8. 🟡 MEDIA: Agregar Pruebas de Seguridad Automatizadas

**Prioridad:** MEDIA  
**Riesgo:** BAJO-MEDIO  
**Esfuerzo:** MEDIO

**Problema:**
- No hay tests específicos de seguridad para validar:
  - Protección contra CSRF
  - Rate limiting
  - Validación de tokens de acceso
  - Permisos y autorización
- 192 archivos de test, pero enfocados en funcionalidad, no en seguridad

**Impacto:**
- Regresiones de seguridad pueden pasar desapercibidas
- Cambios en configuración de seguridad no son validados automáticamente

**Solución Recomendada:**
```ruby
# Crear test/security/csrf_test.rb
class CsrfProtectionTest < ActionDispatch::IntegrationTest
  test "POST requests without CSRF token are rejected" do
    post cards_path, params: { card: { title: "Test" } }
    assert_response :forbidden
  end
end

# Crear test/security/rate_limit_test.rb
class RateLimitTest < ActionDispatch::IntegrationTest
  test "rate limiting prevents brute force on login" do
    11.times do
      post session_path, params: { email: "test@example.com" }
    end
    assert_response :too_many_requests
  end
end

# Crear test/security/authorization_test.rb para validar permisos
```

---

### 9. 🟢 BAJA: Mejorar Documentación de Seguridad

**Prioridad:** BAJA  
**Riesgo:** BAJO  
**Esfuerzo:** BAJO

**Problema:**
- No hay documento SECURITY.md en el repositorio
- Falta documentación sobre:
  - Proceso de reporte de vulnerabilidades
  - Política de divulgación responsable
  - Historial de actualizaciones de seguridad
  - Prácticas de seguridad para desarrolladores

**Impacto:**
- Investigadores de seguridad no saben cómo reportar vulnerabilidades
- Usuarios no conocen el compromiso de seguridad del proyecto
- Nuevos desarrolladores no tienen guías de seguridad

**Solución Recomendada:**
```markdown
# Crear SECURITY.md
## Security Policy

### Reporting a Vulnerability
Please email security@fizzy.do with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

We will respond within 48 hours.

### Supported Versions
| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

### Security Best Practices
1. Always use latest stable version
2. Enable all security headers
3. Keep dependencies updated
4. Follow principle of least privilege
```

---

### 10. 🟢 BAJA: Optimizar Configuración de Content Security Policy

**Prioridad:** BAJA  
**Riesgo:** BAJO  
**Esfuerzo:** BAJO

**Problema:**
- CSP permite `unsafe-inline` para estilos (línea 59 de config/initializers/content_security_policy.rb)
  - **Nota:** Esto es intencional para no interferir con herramientas de usuario y extensiones de accesibilidad
- Política de imágenes demasiado permisiva: `blob:`, `data:`, `https:` (línea 60)
- No hay CSP report-uri configurado por defecto para monitorear violaciones

**Impacto:**
- Equilibrio entre seguridad y accesibilidad: `unsafe-inline` aumenta superficie de ataque XSS pero permite extensiones de usuario
- Posible exfiltración de datos mediante imágenes externas desde dominios no confiables
- Sin visibilidad de intentos de violación de CSP para detectar ataques

**Solución Recomendada:**
```ruby
# Mejorar config/initializers/content_security_policy.rb
# NOTA: La configuración actual permite :unsafe_inline para estilos intencionalmente
# para no interferir con herramientas de usuario y extensiones de accesibilidad.
# Si se decide restringir, considerar usar nonces o hash-based CSP:
policy.style_src :self, :unsafe_inline, *sources.(:style_src)
# Mantener :unsafe_inline o migrar gradualmente a nonces

policy.img_src :self, "data:", "https://*.cloudfront.net", *sources.(:img_src)
# Restringir a dominios específicos en lugar de https: completo cuando sea posible

# Configurar report-uri
config.content_security_policy do |policy|
  # ... configuración existente ...
  policy.report_uri ENV["CSP_REPORT_URI"] || "/csp_reports"
end

# Crear endpoint para recibir reportes
class CspReportsController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def create
    Rails.logger.warn("CSP Violation: #{params.inspect}")
    head :ok
  end
end
```

---

## Hallazgos Adicionales

### Aspectos Positivos Encontrados

1. ✅ **Autenticación Robusta:** Sistema de magic links sin contraseñas reduce riesgo de credential stuffing
2. ✅ **Rate Limiting:** Implementado en endpoints críticos (login, signup, confirmaciones)
3. ✅ **Multi-Tenancy Seguro:** Aislamiento por `account_id` en todos los modelos
4. ✅ **CSRF Protection:** Habilitado por defecto con verificación de tokens
5. ✅ **SSL/TLS:** Configurado correctamente con `force_ssl` en producción
6. ✅ **Secure Tokens:** Uso apropiado de `has_secure_token` y `SecureRandom`
7. ✅ **CI/CD Security:** Pipeline automatizado incluye Brakeman, Bundler Audit, y Gitleaks
8. ✅ **Sanitización HTML:** Configuración de safe list para ActionText
9. ✅ **Parameter Filtering:** Filtrado de parámetros sensibles en logs

### Recomendaciones Generales

1. **Principio de Defensa en Profundidad:** Implementar múltiples capas de seguridad
2. **Principio de Menor Privilegio:** Revisar todos los permisos de usuarios y roles
3. **Seguridad por Diseño:** Incluir revisiones de seguridad en el proceso de desarrollo
4. **Educación Continua:** Capacitar al equipo en OWASP Top 10 y mejores prácticas
5. **Pentesting Regular:** Contratar auditorías de seguridad externas periódicamente

---

## Métricas de Seguridad

| Categoría | Estado | Puntuación |
|-----------|--------|------------|
| Autenticación & Autorización | 🟢 Bueno | 8/10 |
| Protección de Entrada | 🟡 Aceptable | 6/10 |
| Configuración de Seguridad | 🟡 Aceptable | 7/10 |
| Manejo de Errores | 🔴 Necesita Mejora | 4/10 |
| Logging & Monitoreo | 🔴 Necesita Mejora | 3/10 |
| Gestión de Dependencias | 🟡 Aceptable | 6/10 |
| Respaldo & Recuperación | 🔴 Necesita Mejora | 2/10 |
| Testing de Seguridad | 🟡 Aceptable | 5/10 |
| Documentación | 🟡 Aceptable | 6/10 |

**Puntuación Global de Seguridad: 5.2/10** (Aceptable con mejoras necesarias)

---

## Próximos Pasos

1. **Inmediato (Próxima Semana):**
   - Implementar monitoreo de errores
   - Habilitar Permissions Policy
   - Revisar y corregir advertencias de Brakeman

2. **Corto Plazo (Próximo Mes):**
   - Establecer sistema de respaldos automatizados
   - Mejorar logging y auditoría
   - Fortalecer validaciones de modelos

3. **Mediano Plazo (Próximos 3 Meses):**
   - Implementar política de dependencias
   - Crear suite de pruebas de seguridad
   - Mejorar documentación de seguridad

4. **Largo Plazo (Próximos 6 Meses):**
   - Contratar auditoría de seguridad externa
   - Implementar programa de bug bounty
   - Certificación de cumplimiento (SOC 2, ISO 27001)

---

## Conclusión

Fizzy es una aplicación bien construida con fundamentos de seguridad sólidos. La implementación de autenticación sin contraseña, rate limiting, y protecciones CSRF/CSP demuestran un compromiso con la seguridad. Sin embargo, existen áreas críticas que requieren atención inmediata, particularmente en monitoreo de errores, respaldos, y logging de auditoría.

La implementación de las 10 acciones prioritarias listadas en este informe mejorará significativamente la postura de seguridad de la aplicación y reducirá el riesgo de incidentes de seguridad.

---

**Informe generado automáticamente**  
Para preguntas o aclaraciones, contactar al equipo de seguridad.
