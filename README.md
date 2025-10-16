# 🧹 God Strip Meta — Remoção Completa de Metadados de Vídeos MP4

Um script avançado em **Shell Script** para remover **todos os metadados de arquivos MP4**, garantindo que vídeos publicados não deixem rastros de informações sensíveis. Ideal para criadores, pentesters ou labs de privacidade. 
Observação do Autor: Feito com ajuda da IA

---

## 🔹 Recursos

- Remove **tags de arquivo** (ExifTool).  
- Limpa **metadata do container** (FFmpeg, duas passagens para garantia).  
- Suporte extra para **AtomicParsley** e **MP4Box** se instalados.  
- Remove **extended attributes** (xattrs).  
- Padroniza timestamps para **2000-01-01 00:00** (não deixa rastros de datas reais).  
- Verificação final de tags via `ffprobe` e `exiftool`.  
- Sobrescreve arquivos originais, **sem backups**.  

---

## 🔹 Pré-requisitos

- Linux / macOS  
- `bash`  
- Ferramentas instaladas:  
  - [`ffmpeg`](https://ffmpeg.org/)  
  - [`exiftool`](https://exiftool.org/)  
- Opcional (mais limpeza avançada):  
  - [`AtomicParsley`](https://atomicparsley.sourceforge.io/)  
  - [`MP4Box`](https://gpac.wp.imt.fr/mp4box/)  

---

## 🔹 Uso

```bash
./god_strip_meta.sh video1.mp4 video2.mp4 ...
