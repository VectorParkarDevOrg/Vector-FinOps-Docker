import { RefObject, useState } from "react";
import DownloadOutlinedIcon from "@mui/icons-material/DownloadOutlined";
import { saveAs } from "file-saver";
import { FormattedMessage } from "react-intl";
import ButtonLoader from "components/ButtonLoader";
import SnackbarAlert from "components/SnackbarAlert";
import { isEmptyArray } from "utils/arrays";
import { format } from "utils/datetime";
import { createPng } from "utils/exportChart";

type ExportFormat = "png";

type FileNameConfig = {
  title: string;
  fileFormat: ExportFormat;
  withTime?: boolean;
};

type ChartExportProps = {
  chartWrapperRef: RefObject<HTMLElement | null>;
  isLoading: boolean;
  dataTestId?: string;
};

const defaultConfig: FileNameConfig = {
  title: "Vector_chart",
  fileFormat: "png",
  withTime: true
};

const generateFileName = ({ title, fileFormat, withTime }: FileNameConfig): string => {
  let fileName = title;

  if (withTime) {
    fileName += `_${format(new Date(), "HH_mm_ss")}`;
  }

  return fileName + `.${fileFormat}`;
};

const ChartExport = ({ chartWrapperRef, isLoading, dataTestId }: ChartExportProps) => {
  const [showAlert, setShowAlert] = useState(false);

  const handlerDownloadPng = async () => {
    let canvases = Array.from(chartWrapperRef.current?.querySelectorAll("canvas") ?? []);

    // Fallback: try to find canvas using data-test-id if ref-based search fails
    if (isEmptyArray(canvases) && dataTestId) {
      const wrapper = document.querySelector(`[data-test-id="${dataTestId}"]`);
      if (wrapper) {
        canvases = Array.from(wrapper.querySelectorAll("canvas"));
      }
    }

    // Final fallback: find the closest parent with canvas
    if (isEmptyArray(canvases) && chartWrapperRef.current) {
      const parent = chartWrapperRef.current.closest('[data-test-id]');
      if (parent) {
        canvases = Array.from(parent.querySelectorAll("canvas"));
      }
    }

    if (isEmptyArray(canvases)) {
      setShowAlert(true);
      return;
    }

    const fileName = generateFileName(defaultConfig);
    const png = await createPng(canvases);

    if (png) {
      saveAs(png, fileName);
    } else {
      setShowAlert(true);
    }
  };

  return (
    <div>
      <div>
        <ButtonLoader
          uppercase
          dataTestId="btn_export_chart"
          variant="outlined"
          color="primary"
          isLoading={isLoading}
          messageId="exportChart"
          size="small"
          startIcon={<DownloadOutlinedIcon fontSize="small" />}
          onClick={handlerDownloadPng}
        />
      </div>
      <SnackbarAlert
        body={<FormattedMessage id="exportChartError" />}
        openState={showAlert}
        severity="error"
        autoHideDuration={3000}
        handleClose={() => setShowAlert(false)}
      />
    </div>
  );
};

export default ChartExport;
