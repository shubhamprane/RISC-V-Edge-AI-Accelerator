import PyPDF2

try:
    reader = PyPDF2.PdfReader('Group7_Block_Diagram.pdf')
    with open('pdf_text.txt', 'w', encoding='utf-8') as f:
        for page in reader.pages:
            f.write(page.extract_text() + '\n')
    print("Extraction successful.")
except Exception as e:
    print(f"Error: {e}")
