# Papers

This folder stores papers, organized by topics.

For pdfs, a markdown version is or will be provided to facilitate LLM reviews of implementation.

Reading the text embedded in PDF via the traditional engine like pdfium is limited when handling equations, formulas, charts, and tables.
It also wouldn't work for old scanned PDFs.

Hence as of March 2026, we use PaddleOCR-VL-1.5 to transform the pdfs to markdown:
- https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.5
- https://arxiv.org/pdf/2601.21957
- https://github.com/PaddlePaddle/PaddleOCR